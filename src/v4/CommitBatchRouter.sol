// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { SafeCallback } from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { BalanceDelta, BalanceDeltaLibrary } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { IResidualExecutor } from "../interfaces/IResidualExecutor.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";

/// @notice Minimal flash-accounting router for CommitBatch's single authorized residual.
contract CommitBatchRouter is SafeCallback, IResidualExecutor {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeTransferLib for address;

    struct Operation {
        uint64 batchId;
        uint64 nonce;
        bool protocolZeroForOne;
        uint128 amountIn;
        uint160 sqrtPriceLimitX96;
    }

    error Unauthorized();
    error InvalidPool();
    error InvalidDelta();
    error ReentrantCall();
    error PoolAlreadyConfigured();

    address public immutable settlement;
    address public immutable baseToken;
    address public immutable quoteToken;
    address public immutable owner;
    PoolKey public poolKey;
    bool public poolConfigured;
    bool private executing;

    event ResidualExecuted(
        uint64 indexed batchId, uint64 indexed authorizationNonce, bool zeroForOne, uint128 amountIn, uint256 amountOut
    );

    constructor(IPoolManager poolManager_, address settlement_, address baseToken_, address quoteToken_)
        SafeCallback(poolManager_)
    {
        if (
            settlement_ == address(0) || baseToken_ == address(0) || quoteToken_ == address(0)
                || baseToken_ == quoteToken_
        ) revert InvalidPool();
        settlement = settlement_;
        baseToken = baseToken_;
        quoteToken = quoteToken_;
        owner = msg.sender;
    }

    function configurePool(PoolKey calldata poolKey_) external {
        if (msg.sender != owner) revert Unauthorized();
        if (poolConfigured) revert PoolAlreadyConfigured();
        address currency0 = Currency.unwrap(poolKey_.currency0);
        address currency1 = Currency.unwrap(poolKey_.currency1);
        if (
            address(poolKey_.hooks) == address(0)
                || !((currency0 == baseToken && currency1 == quoteToken)
                    || (currency0 == quoteToken && currency1 == baseToken))
        ) revert InvalidPool();
        poolKey = poolKey_;
        poolConfigured = true;
        emit PoolConfigured(currency0, currency1, address(poolKey_.hooks), poolKey_.fee, poolKey_.tickSpacing);
    }

    function executeResidual(
        uint64 batchId,
        uint64 authorizationNonce,
        bool zeroForOne,
        uint128 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountInUsed, uint256 amountOut) {
        if (msg.sender != settlement) revert Unauthorized();
        if (!poolConfigured || executing) revert ReentrantCall();
        executing = true;
        bytes memory result = poolManager.unlock(
            abi.encode(
                Operation({
                    batchId: batchId,
                    nonce: authorizationNonce,
                    protocolZeroForOne: zeroForOne,
                    amountIn: amountIn,
                    sqrtPriceLimitX96: sqrtPriceLimitX96
                })
            )
        );
        executing = false;
        (amountInUsed, amountOut) = abi.decode(result, (uint256, uint256));
        emit ResidualExecuted(batchId, authorizationNonce, zeroForOne, amountIn, amountOut);
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        if (!executing) revert ReentrantCall();
        Operation memory operation = abi.decode(data, (Operation));
        bool poolZeroForOne = Currency.unwrap(poolKey.currency0) == baseToken
            ? operation.protocolZeroForOne
            : !operation.protocolZeroForOne;
        SwapParams memory params = SwapParams({
            zeroForOne: poolZeroForOne,
            amountSpecified: -int256(uint256(operation.amountIn)),
            sqrtPriceLimitX96: operation.sqrtPriceLimitX96
        });
        bytes memory hookData = abi.encode(
            operation.batchId,
            operation.nonce,
            operation.protocolZeroForOne,
            operation.amountIn,
            operation.sqrtPriceLimitX96
        );
        BalanceDelta delta = poolManager.swap(poolKey, params, hookData);
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        _settleOrTake(poolKey.currency0, amount0);
        _settleOrTake(poolKey.currency1, amount1);

        int128 inputDelta = poolZeroForOne ? amount0 : amount1;
        int128 outputDelta = poolZeroForOne ? amount1 : amount0;
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidDelta();
        return abi.encode(uint256(-int256(inputDelta)), uint256(uint128(outputDelta)));
    }

    function _settleOrTake(Currency currency, int128 delta) private {
        if (delta < 0) {
            uint256 amount = uint256(-int256(delta));
            poolManager.sync(currency);
            Currency.unwrap(currency).safeTransferFrom(settlement, address(poolManager), amount);
            poolManager.settle();
        } else if (delta > 0) {
            poolManager.take(currency, settlement, uint256(uint128(delta)));
        }
    }

    event PoolConfigured(
        address indexed currency0, address indexed currency1, address indexed hook, uint24 fee, int24 tickSpacing
    );
}
