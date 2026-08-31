// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { BaseHook } from "v4-hooks-public/base/BaseHook.sol";
import { SafeCallback } from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import { PoolManager } from "@uniswap/v4-core/src/PoolManager.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { BalanceDelta, BalanceDeltaLibrary } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { CommitBatch } from "../../src/core/CommitBatch.sol";
import { CommitBatchHook, ICommitBatchAuthorization } from "../../src/hook/CommitBatchHook.sol";
import { CommitBatchRouter } from "../../src/v4/CommitBatchRouter.sol";
import { OrderHash } from "../../src/libraries/OrderHash.sol";
import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { MockReferencePrice } from "../../src/mocks/MockReferencePrice.sol";

contract TestableCommitBatchHook is CommitBatchHook {
    constructor(IPoolManager manager, ICommitBatchAuthorization settlement, address router, address base, address quote)
        CommitBatchHook(manager, settlement, router, base, quote)
    { }

    function validateHookAddress(BaseHook) internal pure override { }
}

contract TestLiquidityRouter is SafeCallback {
    using BalanceDeltaLibrary for BalanceDelta;

    PoolKey public poolKey;
    address public immutable payer;

    constructor(IPoolManager manager, PoolKey memory key, address payer_) SafeCallback(manager) {
        poolKey = key;
        payer = payer_;
    }

    function add(uint128 liquidity) external {
        poolManager.unlock(abi.encode(liquidity));
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
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
        MockERC20(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount);
        poolManager.settle();
    }
}

contract RealV4ResidualTest is Test {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CALLBACK_PROXY = address(0xCA11BAC);
    address private constant RVM_ID = address(0xBEEF);
    uint160 private constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

    function test_ResidualRunsThroughRealPoolManagerAndHook() public {
        PoolManager manager = new PoolManager(address(this));
        MockERC20 first = new MockERC20("Token A", "A", 18);
        MockERC20 second = new MockERC20("Token B", "B", 18);
        MockERC20 base = address(first) < address(second) ? first : second;
        MockERC20 quote = address(first) < address(second) ? second : first;
        MockReferencePrice priceSource = new MockReferencePrice(address(this), 1e18);
        CommitBatch settlement =
            new CommitBatch(address(this), address(base), address(quote), 18, priceSource, CALLBACK_PROXY, 30);

        uint64 nextNonce = vm.getNonce(address(this));
        address predictedRouter = vm.computeCreateAddress(address(this), nextNonce + 1);
        TestableCommitBatchHook implementation = new TestableCommitBatchHook(
            manager, ICommitBatchAuthorization(address(settlement)), predictedRouter, address(base), address(quote)
        );
        address hookAddress = address(0x80);
        vm.etch(hookAddress, address(implementation).code);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(base)),
            currency1: Currency.wrap(address(quote)),
            fee: 3_000,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });
        CommitBatchRouter router = new CommitBatchRouter(manager, address(settlement), address(base), address(quote));
        assertEq(address(router), predictedRouter);
        router.configurePool(key);
        settlement.configureIntegrations(address(router), hookAddress, RVM_ID);

        manager.initialize(key, SQRT_PRICE_1_1);
        TestLiquidityRouter liquidityRouter = new TestLiquidityRouter(manager, key, address(this));
        base.mint(address(this), 1e30);
        quote.mint(address(this), 1e30);
        base.approve(address(liquidityRouter), type(uint256).max);
        quote.approve(address(liquidityRouter), type(uint256).max);
        liquidityRouter.add(1e24);

        base.mint(ALICE, 10 ether);
        quote.mint(BOB, 7 ether);
        vm.prank(ALICE);
        base.approve(address(settlement), type(uint256).max);
        vm.prank(BOB);
        quote.approve(address(settlement), type(uint256).max);

        settlement.createBatch(10, 10);
        OrderHash.Order memory aliceOrder = OrderHash.Order(1, ALICE, true, 10 ether, 9 ether, ALICE, 1);
        OrderHash.Order memory bobOrder = OrderHash.Order(1, BOB, false, 7 ether, 7 ether, BOB, 1);
        bytes32 aliceSalt = keccak256("alice-v4");
        bytes32 bobSalt = keccak256("bob-v4");
        bytes32 aliceCommitment = settlement.hashOrder(aliceOrder, aliceSalt);
        bytes32 bobCommitment = settlement.hashOrder(bobOrder, bobSalt);
        vm.prank(ALICE);
        settlement.commit(1, aliceCommitment, true, 10 ether);
        vm.prank(BOB);
        settlement.commit(1, bobCommitment, false, 7 ether);

        vm.warp(settlement.getBatch(1).commitDeadline);
        settlement.closeCommit(1);
        vm.prank(ALICE);
        settlement.reveal(aliceOrder, aliceSalt);
        vm.prank(BOB);
        settlement.reveal(bobOrder, bobSalt);
        vm.warp(settlement.getBatch(1).revealDeadline);
        settlement.closeReveal(1);

        vm.prank(CALLBACK_PROXY);
        settlement.settleBatch(RVM_ID, 1, 1, 4_295_128_740);
        CommitBatch.Batch memory batch = settlement.getBatch(1);
        assertEq(batch.matchedBase, 7 ether);
        assertEq(batch.residualIn, 3 ether);
        assertGt(batch.residualOut, 0);
        assertEq(uint8(batch.phase), uint8(CommitBatch.Phase.Settled));
    }
}
