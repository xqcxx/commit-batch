// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { SafeCallback } from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { BalanceDelta, BalanceDeltaLibrary } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";

/// @notice One-purpose full-range ERC-20 liquidity seeder for the testnet demo pool.
contract CommitBatchLiquiditySeeder is SafeCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeTransferLib for address;

    error Unauthorized();
    error ReentrantCall();

    address public immutable owner;
    PoolKey public poolKey;
    bool private executing;

    constructor(IPoolManager poolManager_, PoolKey memory poolKey_, address owner_) SafeCallback(poolManager_) {
        if (owner_ == address(0)) revert Unauthorized();
        owner = owner_;
        poolKey = poolKey_;
    }

    function seed(uint128 liquidity) external {
        if (msg.sender != owner) revert Unauthorized();
        if (executing) revert ReentrantCall();
        executing = true;
        poolManager.unlock(abi.encode(liquidity));
        executing = false;
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        if (!executing) revert Unauthorized();
        uint128 liquidity = abi.decode(data, (uint128));
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -887_220, tickUpper: 887_220, liquidityDelta: int256(uint256(liquidity)), salt: bytes32(0)
            }),
            ""
        );
        _settle(poolKey.currency0, delta.amount0());
        _settle(poolKey.currency1, delta.amount1());
        return "";
    }

    function _settle(Currency currency, int128 delta) private {
        if (delta >= 0) return;
        uint256 amount = uint256(-int256(delta));
        poolManager.sync(currency);
        Currency.unwrap(currency).safeTransferFrom(owner, address(poolManager), amount);
        poolManager.settle();
    }
}
