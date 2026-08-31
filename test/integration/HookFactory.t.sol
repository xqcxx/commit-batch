// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { PoolManager } from "@uniswap/v4-core/src/PoolManager.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { CommitBatch } from "../../src/core/CommitBatch.sol";
import { CommitBatchHook, ICommitBatchAuthorization } from "../../src/hook/CommitBatchHook.sol";
import { CommitBatchHookFactory } from "../../src/deploy/CommitBatchHookFactory.sol";
import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { MockReferencePrice } from "../../src/mocks/MockReferencePrice.sol";

contract HookFactoryTest is Test {
    function test_MinesAndDeploysBeforeSwapPermissionAddress() public {
        PoolManager manager = new PoolManager(address(this));
        MockERC20 base = new MockERC20("Base", "BASE", 18);
        MockERC20 quote = new MockERC20("Quote", "QUOTE", 6);
        MockReferencePrice price = new MockReferencePrice(address(this), 2_000e18);
        CommitBatch batch =
            new CommitBatch(address(this), address(base), address(quote), 6, price, address(0xCA11BAC), 30);
        CommitBatchHookFactory factory = new CommitBatchHookFactory();
        address router = address(0xBEEF);

        (bytes32 salt, address predicted) = factory.findSalt(
            manager, ICommitBatchAuthorization(address(batch)), router, address(base), address(quote), 0, 100_000
        );
        assertEq(uint160(predicted) & ((1 << 14) - 1), 1 << 7);
        CommitBatchHook hook = factory.deploy(
            salt, manager, ICommitBatchAuthorization(address(batch)), router, address(base), address(quote)
        );
        assertEq(address(hook), predicted);
        assertEq(address(hook.poolManager()), address(manager));
    }
}
