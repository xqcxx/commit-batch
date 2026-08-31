// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IResidualExecutor } from "../interfaces/IResidualExecutor.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";

interface IResidualAuthorizationConsumer {
    function consumeResidualAuthorization(
        address callbackSender,
        uint64 batchId,
        uint64 nonce,
        bool zeroForOne,
        uint128 amountIn,
        uint160 sqrtPriceLimitX96
    ) external;
}

/// @notice Deterministic local substitute for the router and hook; testnet uses the real v4 path.
contract MockResidualExecutor is IResidualExecutor {
    using SafeTransferLib for address;

    address public immutable settlement;
    address public immutable baseToken;
    address public immutable quoteToken;
    uint256 public baseSaleOutput;
    uint256 public quoteSaleOutput;
    uint256 public inputUsed;

    constructor(address settlement_, address baseToken_, address quoteToken_) {
        settlement = settlement_;
        baseToken = baseToken_;
        quoteToken = quoteToken_;
    }

    function setOutputs(uint256 baseSaleOutput_, uint256 quoteSaleOutput_) external {
        baseSaleOutput = baseSaleOutput_;
        quoteSaleOutput = quoteSaleOutput_;
    }

    /// @dev Zero preserves full consumption, which is the canonical demo behavior.
    function setInputUsed(uint256 inputUsed_) external {
        inputUsed = inputUsed_;
    }

    function executeResidual(
        uint64 batchId,
        uint64 authorizationNonce,
        bool zeroForOne,
        uint128 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountInUsed, uint256 amountOut) {
        require(msg.sender == settlement, "settlement only");
        IResidualAuthorizationConsumer(settlement)
            .consumeResidualAuthorization(
                address(this), batchId, authorizationNonce, zeroForOne, amountIn, sqrtPriceLimitX96
            );
        address input = zeroForOne ? baseToken : quoteToken;
        address output = zeroForOne ? quoteToken : baseToken;
        amountInUsed = inputUsed == 0 ? amountIn : inputUsed;
        require(amountInUsed <= amountIn, "input exceeds authorization");
        amountOut = zeroForOne ? baseSaleOutput : quoteSaleOutput;
        input.safeTransferFrom(settlement, address(this), amountInUsed);
        output.safeTransfer(settlement, amountOut);
    }
}
