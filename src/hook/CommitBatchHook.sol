// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BaseHook } from "v4-hooks-public/base/BaseHook.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { BeforeSwapDelta, BeforeSwapDeltaLibrary } from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

interface ICommitBatchAuthorization {
    function consumeResidualAuthorization(
        address callbackSender,
        uint64 batchId,
        uint64 nonce,
        bool zeroForOne,
        uint128 amountIn,
        uint160 sqrtPriceLimitX96
    ) external;
}

/// @notice Exclusive v4 execution-lane hook for one controller-authorized residual swap.
contract CommitBatchHook is BaseHook {
    error InvalidPool();
    error UnauthorizedRouter();
    error InvalidSwap();

    ICommitBatchAuthorization public immutable settlement;
    address public immutable router;
    address public immutable baseToken;
    address public immutable quoteToken;

    event ResidualValidated(
        uint64 indexed batchId, uint64 indexed authorizationNonce, bool zeroForOne, uint128 amountIn
    );

    constructor(
        IPoolManager poolManager_,
        ICommitBatchAuthorization settlement_,
        address router_,
        address baseToken_,
        address quoteToken_
    ) BaseHook(poolManager_) {
        if (
            address(settlement_) == address(0) || router_ == address(0) || baseToken_ == address(0)
                || quoteToken_ == address(0) || baseToken_ == quoteToken_
        ) revert InvalidPool();
        settlement = settlement_;
        router = router_;
        baseToken = baseToken_;
        quoteToken = quoteToken_;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions.beforeSwap = true;
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (sender != router) revert UnauthorizedRouter();
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        if (!((currency0 == baseToken && currency1 == quoteToken)
                    || (currency0 == quoteToken && currency1 == baseToken))) {
            revert InvalidPool();
        }

        (uint64 batchId, uint64 nonce, bool protocolZeroForOne, uint128 amountIn, uint160 sqrtPriceLimitX96) =
            abi.decode(hookData, (uint64, uint64, bool, uint128, uint160));
        bool expectedPoolDirection = currency0 == baseToken ? protocolZeroForOne : !protocolZeroForOne;
        if (
            params.amountSpecified >= 0 || uint256(-params.amountSpecified) != amountIn
                || params.zeroForOne != expectedPoolDirection || params.sqrtPriceLimitX96 != sqrtPriceLimitX96
        ) revert InvalidSwap();

        settlement.consumeResidualAuthorization(sender, batchId, nonce, protocolZeroForOne, amountIn, sqrtPriceLimitX96);
        emit ResidualValidated(batchId, nonce, protocolZeroForOne, amountIn);
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
}
