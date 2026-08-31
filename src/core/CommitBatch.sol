// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IReferencePrice } from "../interfaces/IReferencePrice.sol";
import { IResidualExecutor } from "../interfaces/IResidualExecutor.sol";
import { OrderHash } from "../libraries/OrderHash.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { UniformClearing } from "./UniformClearing.sol";

/// @notice Escrows and uniformly nets one opposite pair of commitment-bound exact-input orders.
/// @dev `zeroForOne` means base-to-quote at the protocol layer; the router maps it to pool currency ordering.
contract CommitBatch {
    using SafeTransferLib for address;

    enum Phase {
        None,
        Commit,
        Reveal,
        Ready,
        Settled,
        Cancelled
    }

    struct Batch {
        uint64 commitDeadline;
        uint64 revealDeadline;
        uint64 cancelAfter;
        uint64 callbackNonce;
        uint8 commitmentCount;
        uint8 revealedCount;
        Phase phase;
        uint256 clearingPriceX18;
        uint128 matchedBase;
        uint128 matchedQuote;
        bool residualZeroForOne;
        uint128 residualIn;
        uint128 residualOut;
    }

    struct Commitment {
        bytes32 orderHash;
        address owner;
        bool zeroForOne;
        uint128 depositedAmount;
        bool revealed;
        bool eligible;
        bool claimed;
        bool refunded;
        OrderHash.Order order;
    }

    struct ResidualAuthorization {
        uint64 batchId;
        uint64 nonce;
        bool zeroForOne;
        uint128 amountIn;
        uint160 sqrtPriceLimitX96;
        bool active;
    }

    error Unauthorized();
    error InvalidAddress();
    error InvalidDeadline();
    error InvalidPhase();
    error BatchFull();
    error DirectionConflict();
    error DuplicateOwner();
    error UnknownCommitment();
    error CommitmentMismatch();
    error NonceUsed();
    error AlreadyProcessed();
    error InvalidCallback();
    error IntegrationAlreadySet();
    error IntegrationNotSet();
    error ResidualMismatch();
    error MinimumOutputNotMet();
    error ReentrantCall();

    address public immutable owner;
    address public immutable baseToken;
    address public immutable quoteToken;
    uint8 public immutable quoteDecimals;
    IReferencePrice public immutable referencePrice;
    address public immutable callbackProxy;
    uint64 public immutable cancellationDelay;

    address public expectedRvmId;
    address public residualRouter;
    address public residualHook;
    uint64 public nextBatchId;
    uint64 public nextCallbackNonce;
    uint64 public nextResidualNonce;

    mapping(uint64 batchId => Batch) public batches;
    mapping(uint64 batchId => mapping(uint8 slot => Commitment)) private commitments;
    mapping(uint64 batchId => mapping(bytes32 orderHash => uint8 indexPlusOne)) private commitmentIndex;
    mapping(address account => mapping(uint64 nonce => bool used)) public usedNonces;
    mapping(bytes32 orderHash => mapping(address token => uint256 amount)) public claimable;

    ResidualAuthorization public residualAuthorization;
    bool private entered;

    event BatchCreated(uint64 indexed batchId, uint64 commitDeadline, uint64 revealDeadline, uint64 cancelAfter);
    event OrderCommitted(uint64 indexed batchId, bytes32 indexed commitment, address indexed owner);
    event CommitClosed(uint64 indexed batchId, uint256 clearingPriceX18);
    event OrderRevealed(
        uint64 indexed batchId,
        bytes32 indexed commitment,
        address indexed owner,
        bool zeroForOne,
        uint128 amountIn,
        bool eligible
    );
    event SettlementRequested(uint64 indexed batchId, uint64 indexed callbackNonce);
    event InternalFlowMatched(uint64 indexed batchId, uint128 matchedBase, uint128 matchedQuote, uint256 priceX18);
    event ResidualAuthorized(
        uint64 indexed batchId, uint64 indexed nonce, bool zeroForOne, uint128 amountIn, uint160 sqrtPriceLimitX96
    );
    event ResidualAuthorizationConsumed(uint64 indexed batchId, uint64 indexed nonce);
    event BatchSettled(
        uint64 indexed batchId,
        uint128 matchedBase,
        uint128 matchedQuote,
        bool residualZeroForOne,
        uint128 residualIn,
        uint128 residualOut
    );
    event BatchCancelled(uint64 indexed batchId);
    event OrderClaimed(
        uint64 indexed batchId, bytes32 indexed commitment, address indexed recipient, address token, uint256 amount
    );
    event OrderRefunded(
        uint64 indexed batchId, bytes32 indexed commitment, address indexed owner, address token, uint256 amount
    );
    event IntegrationsConfigured(address indexed router, address indexed hook, address indexed rvmId);

    constructor(
        address owner_,
        address baseToken_,
        address quoteToken_,
        uint8 quoteDecimals_,
        IReferencePrice referencePrice_,
        address callbackProxy_,
        uint64 cancellationDelay_
    ) {
        if (
            owner_ == address(0) || baseToken_ == address(0) || quoteToken_ == address(0)
                || address(referencePrice_) == address(0) || callbackProxy_ == address(0) || baseToken_ == quoteToken_
        ) revert InvalidAddress();
        if (quoteDecimals_ > 18 || cancellationDelay_ == 0) revert InvalidDeadline();
        owner = owner_;
        baseToken = baseToken_;
        quoteToken = quoteToken_;
        quoteDecimals = quoteDecimals_;
        referencePrice = referencePrice_;
        callbackProxy = callbackProxy_;
        cancellationDelay = cancellationDelay_;
    }

    modifier nonReentrant() {
        if (entered) revert ReentrantCall();
        entered = true;
        _;
        entered = false;
    }

    function configureIntegrations(address router, address hook, address rvmId) external {
        if (msg.sender != owner) revert Unauthorized();
        if (residualRouter != address(0) || residualHook != address(0) || expectedRvmId != address(0)) {
            revert IntegrationAlreadySet();
        }
        if (router == address(0) || hook == address(0) || rvmId == address(0)) revert InvalidAddress();
        residualRouter = router;
        residualHook = hook;
        expectedRvmId = rvmId;
        baseToken.safeApprove(router, type(uint256).max);
        quoteToken.safeApprove(router, type(uint256).max);
        emit IntegrationsConfigured(router, hook, rvmId);
    }

    function createBatch(uint64 commitDuration, uint64 revealDuration) external returns (uint64 batchId) {
        if (commitDuration == 0 || revealDuration == 0) revert InvalidDeadline();
        batchId = ++nextBatchId;
        uint64 commitDeadline = uint64(block.timestamp) + commitDuration;
        uint64 revealDeadline = commitDeadline + revealDuration;
        uint64 cancelAfter = revealDeadline + cancellationDelay;
        batches[batchId] = Batch({
            commitDeadline: commitDeadline,
            revealDeadline: revealDeadline,
            cancelAfter: cancelAfter,
            callbackNonce: 0,
            commitmentCount: 0,
            revealedCount: 0,
            phase: Phase.Commit,
            clearingPriceX18: 0,
            matchedBase: 0,
            matchedQuote: 0,
            residualZeroForOne: false,
            residualIn: 0,
            residualOut: 0
        });
        emit BatchCreated(batchId, commitDeadline, revealDeadline, cancelAfter);
    }

    function commit(uint64 batchId, bytes32 orderCommitment, bool zeroForOne, uint128 depositAmount)
        external
        nonReentrant
    {
        Batch storage batch = batches[batchId];
        if (batch.phase != Phase.Commit || block.timestamp >= batch.commitDeadline) revert InvalidPhase();
        if (batch.commitmentCount == 2) revert BatchFull();
        if (orderCommitment == bytes32(0) || depositAmount == 0) revert CommitmentMismatch();

        uint8 slot = batch.commitmentCount;
        if (slot == 1) {
            Commitment storage first = commitments[batchId][0];
            if (first.zeroForOne == zeroForOne) revert DirectionConflict();
            if (first.owner == msg.sender) revert DuplicateOwner();
        }
        if (commitmentIndex[batchId][orderCommitment] != 0) revert CommitmentMismatch();

        commitments[batchId][slot] = Commitment({
            orderHash: orderCommitment,
            owner: msg.sender,
            zeroForOne: zeroForOne,
            depositedAmount: depositAmount,
            revealed: false,
            eligible: false,
            claimed: false,
            refunded: false,
            order: OrderHash.Order(0, address(0), false, 0, 0, address(0), 0)
        });
        commitmentIndex[batchId][orderCommitment] = slot + 1;
        batch.commitmentCount = slot + 1;

        (zeroForOne ? baseToken : quoteToken).safeTransferFrom(msg.sender, address(this), depositAmount);
        emit OrderCommitted(batchId, orderCommitment, msg.sender);
    }

    function closeCommit(uint64 batchId) external {
        Batch storage batch = batches[batchId];
        if (batch.phase != Phase.Commit || block.timestamp < batch.commitDeadline) revert InvalidPhase();
        batch.clearingPriceX18 = referencePrice.priceX18();
        batch.phase = Phase.Reveal;
        emit CommitClosed(batchId, batch.clearingPriceX18);
    }

    function reveal(OrderHash.Order calldata order, bytes32 salt) external {
        Batch storage batch = batches[order.batchId];
        if (batch.phase != Phase.Reveal || block.timestamp >= batch.revealDeadline) revert InvalidPhase();

        bytes32 orderCommitment = OrderHash.hash(order, salt);
        uint8 indexPlusOne = commitmentIndex[order.batchId][orderCommitment];
        if (indexPlusOne == 0) revert UnknownCommitment();
        Commitment storage stored = commitments[order.batchId][indexPlusOne - 1];
        if (
            stored.revealed || stored.owner != msg.sender || order.owner != msg.sender
                || stored.zeroForOne != order.zeroForOne || stored.depositedAmount != order.amountIn
                || order.recipient == address(0)
        ) revert CommitmentMismatch();
        if (usedNonces[msg.sender][order.nonce]) revert NonceUsed();

        uint256 referenceOutput = order.zeroForOne
            ? UniformClearing.quoteForBase(order.amountIn, batch.clearingPriceX18, quoteDecimals)
            : UniformClearing.baseForQuote(order.amountIn, batch.clearingPriceX18, quoteDecimals);
        bool eligible = referenceOutput >= order.minAmountOut;

        stored.revealed = true;
        stored.eligible = eligible;
        stored.order = order;
        usedNonces[msg.sender][order.nonce] = true;
        ++batch.revealedCount;
        emit OrderRevealed(order.batchId, orderCommitment, msg.sender, order.zeroForOne, order.amountIn, eligible);
    }

    function closeReveal(uint64 batchId) external {
        Batch storage batch = batches[batchId];
        if (batch.phase != Phase.Reveal || block.timestamp < batch.revealDeadline) revert InvalidPhase();

        if (
            batch.commitmentCount != 2 || batch.revealedCount != 2 || !commitments[batchId][0].eligible
                || !commitments[batchId][1].eligible
        ) {
            batch.phase = Phase.Cancelled;
            emit BatchCancelled(batchId);
            return;
        }

        batch.phase = Phase.Ready;
        batch.callbackNonce = ++nextCallbackNonce;
        emit SettlementRequested(batchId, batch.callbackNonce);
    }

    function settleBatch(address rvmId, uint64 batchId, uint64 callbackNonce, uint160 sqrtPriceLimitX96)
        external
        nonReentrant
    {
        if (msg.sender != callbackProxy || rvmId != expectedRvmId) revert InvalidCallback();
        if (residualRouter == address(0) || residualHook == address(0)) revert IntegrationNotSet();
        Batch storage batch = batches[batchId];
        if (batch.phase != Phase.Ready || batch.callbackNonce != callbackNonce) revert InvalidCallback();

        (Commitment storage baseOrder, Commitment storage quoteOrder) = _directionalOrders(batchId);
        UniformClearing.Result memory result = UniformClearing.clear(
            baseOrder.depositedAmount, quoteOrder.depositedAmount, batch.clearingPriceX18, quoteDecimals
        );

        uint256 baseOutput = result.matchedBase;
        uint256 quoteOutput = result.matchedQuote;
        uint256 residualInputUsed;
        uint256 residualOutput;

        if (result.residualIn != 0) {
            uint64 authorizationNonce = ++nextResidualNonce;
            residualAuthorization = ResidualAuthorization({
                batchId: batchId,
                nonce: authorizationNonce,
                zeroForOne: result.residualZeroForOne,
                amountIn: result.residualIn,
                sqrtPriceLimitX96: sqrtPriceLimitX96,
                active: true
            });
            emit ResidualAuthorized(
                batchId, authorizationNonce, result.residualZeroForOne, result.residualIn, sqrtPriceLimitX96
            );
            (residualInputUsed, residualOutput) = IResidualExecutor(residualRouter)
                .executeResidual(
                    batchId, authorizationNonce, result.residualZeroForOne, result.residualIn, sqrtPriceLimitX96
                );
            if (residualAuthorization.active) revert ResidualMismatch();
            if (residualInputUsed > result.residualIn || residualOutput > type(uint128).max) revert ResidualMismatch();

            if (result.residualZeroForOne) quoteOutput += residualOutput;
            else baseOutput += residualOutput;
        }

        if (quoteOutput < baseOrder.order.minAmountOut || baseOutput < quoteOrder.order.minAmountOut) {
            revert MinimumOutputNotMet();
        }

        claimable[baseOrder.orderHash][quoteToken] = quoteOutput;
        claimable[quoteOrder.orderHash][baseToken] = baseOutput;
        if (result.residualIn > residualInputUsed) {
            Commitment storage residualOwner = result.residualZeroForOne ? baseOrder : quoteOrder;
            address residualToken = result.residualZeroForOne ? baseToken : quoteToken;
            claimable[residualOwner.orderHash][residualToken] = result.residualIn - residualInputUsed;
        }
        batch.matchedBase = result.matchedBase;
        batch.matchedQuote = result.matchedQuote;
        batch.residualZeroForOne = result.residualZeroForOne;
        batch.residualIn = result.residualIn;
        batch.residualOut = uint128(residualOutput);
        batch.phase = Phase.Settled;

        emit InternalFlowMatched(batchId, result.matchedBase, result.matchedQuote, batch.clearingPriceX18);
        emit BatchSettled(
            batchId,
            result.matchedBase,
            result.matchedQuote,
            result.residualZeroForOne,
            result.residualIn,
            uint128(residualOutput)
        );
    }

    function consumeResidualAuthorization(
        address callbackSender,
        uint64 batchId,
        uint64 nonce,
        bool zeroForOne,
        uint128 amountIn,
        uint160 sqrtPriceLimitX96
    ) external {
        if (msg.sender != residualHook || callbackSender != residualRouter) revert Unauthorized();
        ResidualAuthorization storage authorization = residualAuthorization;
        if (
            !authorization.active || authorization.batchId != batchId || authorization.nonce != nonce
                || authorization.zeroForOne != zeroForOne || authorization.amountIn != amountIn
                || authorization.sqrtPriceLimitX96 != sqrtPriceLimitX96
        ) revert ResidualMismatch();
        authorization.active = false;
        emit ResidualAuthorizationConsumed(batchId, nonce);
    }

    function cancelStaleBatch(uint64 batchId) external {
        Batch storage batch = batches[batchId];
        if (batch.phase != Phase.Ready || block.timestamp < batch.cancelAfter) revert InvalidPhase();
        batch.phase = Phase.Cancelled;
        emit BatchCancelled(batchId);
    }

    function claim(uint64 batchId, bytes32 orderCommitment) external nonReentrant returns (uint256 amount) {
        Batch storage batch = batches[batchId];
        if (batch.phase != Phase.Settled) revert InvalidPhase();
        Commitment storage stored = _commitment(batchId, orderCommitment);
        if (stored.owner != msg.sender) revert Unauthorized();
        if (stored.claimed || stored.refunded) revert AlreadyProcessed();

        address outputToken = stored.zeroForOne ? quoteToken : baseToken;
        address inputToken = stored.zeroForOne ? baseToken : quoteToken;
        amount = claimable[orderCommitment][outputToken];
        uint256 unusedInput = claimable[orderCommitment][inputToken];
        if (amount == 0 && unusedInput == 0) revert AlreadyProcessed();
        stored.claimed = true;
        claimable[orderCommitment][outputToken] = 0;
        claimable[orderCommitment][inputToken] = 0;
        if (amount != 0) {
            outputToken.safeTransfer(stored.order.recipient, amount);
            emit OrderClaimed(batchId, orderCommitment, stored.order.recipient, outputToken, amount);
        }
        if (unusedInput != 0) {
            inputToken.safeTransfer(stored.order.recipient, unusedInput);
            emit OrderClaimed(batchId, orderCommitment, stored.order.recipient, inputToken, unusedInput);
        }
    }

    function refund(uint64 batchId, bytes32 orderCommitment) external nonReentrant returns (uint256 amount) {
        if (batches[batchId].phase != Phase.Cancelled) revert InvalidPhase();
        Commitment storage stored = _commitment(batchId, orderCommitment);
        if (stored.owner != msg.sender) revert Unauthorized();
        if (stored.claimed || stored.refunded) revert AlreadyProcessed();
        stored.refunded = true;
        amount = stored.depositedAmount;
        address inputToken = stored.zeroForOne ? baseToken : quoteToken;
        inputToken.safeTransfer(stored.owner, amount);
        emit OrderRefunded(batchId, orderCommitment, stored.owner, inputToken, amount);
    }

    function getCommitment(uint64 batchId, uint8 slot) external view returns (Commitment memory) {
        if (slot >= batches[batchId].commitmentCount) revert UnknownCommitment();
        return commitments[batchId][slot];
    }

    function getBatch(uint64 batchId) external view returns (Batch memory) {
        return batches[batchId];
    }

    function hashOrder(OrderHash.Order calldata order, bytes32 salt) external pure returns (bytes32) {
        return OrderHash.hash(order, salt);
    }

    function _commitment(uint64 batchId, bytes32 orderCommitment) private view returns (Commitment storage stored) {
        uint8 indexPlusOne = commitmentIndex[batchId][orderCommitment];
        if (indexPlusOne == 0) revert UnknownCommitment();
        stored = commitments[batchId][indexPlusOne - 1];
    }

    function _directionalOrders(uint64 batchId)
        private
        view
        returns (Commitment storage baseOrder, Commitment storage quoteOrder)
    {
        Commitment storage first = commitments[batchId][0];
        Commitment storage second = commitments[batchId][1];
        if (first.zeroForOne) return (first, second);
        return (second, first);
    }
}
