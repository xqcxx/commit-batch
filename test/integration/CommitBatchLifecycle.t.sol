// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { CommitBatch } from "../../src/core/CommitBatch.sol";
import { OrderHash } from "../../src/libraries/OrderHash.sol";
import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { MockReferencePrice } from "../../src/mocks/MockReferencePrice.sol";
import { MockResidualExecutor } from "../../src/mocks/MockResidualExecutor.sol";

contract CommitBatchLifecycleTest is Test {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CALLBACK_PROXY = address(0xCA11BAC);
    address private constant RVM_ID = address(0xBEEF);
    uint160 private constant PRICE_LIMIT = 4_295_128_740;

    MockERC20 private weth;
    MockERC20 private usdc;
    MockReferencePrice private priceSource;
    CommitBatch private settlement;
    MockResidualExecutor private executor;

    OrderHash.Order private aliceOrder;
    OrderHash.Order private bobOrder;
    bytes32 private aliceSalt = keccak256("alice-demo-salt");
    bytes32 private bobSalt = keccak256("bob-demo-salt");
    bytes32 private aliceCommitment;
    bytes32 private bobCommitment;

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("Demo USD Coin", "USDC", 6);
        priceSource = new MockReferencePrice(address(this), 2_000e18);
        settlement = new CommitBatch(address(this), address(weth), address(usdc), 6, priceSource, CALLBACK_PROXY, 30);
        executor = new MockResidualExecutor(address(settlement), address(weth), address(usdc));
        settlement.configureIntegrations(address(executor), address(executor), RVM_ID);

        weth.mint(ALICE, 10 ether);
        usdc.mint(BOB, 14_000e6);
        usdc.mint(address(executor), 5_970e6);
        weth.mint(address(executor), 10 ether);
        executor.setOutputs(5_970e6, 2 ether);

        vm.prank(ALICE);
        weth.approve(address(settlement), type(uint256).max);
        vm.prank(BOB);
        usdc.approve(address(settlement), type(uint256).max);

        aliceOrder = OrderHash.Order({
            batchId: 1,
            owner: ALICE,
            zeroForOne: true,
            amountIn: 10 ether,
            minAmountOut: 19_900e6,
            recipient: ALICE,
            nonce: 1
        });
        bobOrder = OrderHash.Order({
            batchId: 1,
            owner: BOB,
            zeroForOne: false,
            amountIn: 14_000e6,
            minAmountOut: 7 ether,
            recipient: BOB,
            nonce: 1
        });
        aliceCommitment = settlement.hashOrder(aliceOrder, aliceSalt);
        bobCommitment = settlement.hashOrder(bobOrder, bobSalt);
    }

    function test_FullLifecycleNetsBeforeResidualAndClaims() public {
        _commitBoth();
        _closeAndRevealBoth();
        _requestAndSettle();

        CommitBatch.Batch memory batch = settlement.getBatch(1);
        assertEq(uint8(batch.phase), uint8(CommitBatch.Phase.Settled));
        assertEq(batch.matchedBase, 7 ether);
        assertEq(batch.matchedQuote, 14_000e6);
        assertEq(batch.residualIn, 3 ether);
        assertEq(batch.residualOut, 5_970e6);
        assertEq(weth.balanceOf(address(executor)), 13 ether);

        vm.prank(ALICE);
        assertEq(settlement.claim(1, aliceCommitment), 19_970e6);
        vm.prank(BOB);
        assertEq(settlement.claim(1, bobCommitment), 7 ether);
        assertEq(usdc.balanceOf(ALICE), 19_970e6);
        assertEq(weth.balanceOf(BOB), 7 ether);
    }

    function test_InvalidSaltCannotReveal() public {
        _commitBoth();
        vm.warp(settlement.getBatch(1).commitDeadline);
        settlement.closeCommit(1);
        vm.prank(ALICE);
        vm.expectRevert(CommitBatch.UnknownCommitment.selector);
        settlement.reveal(aliceOrder, bytes32(uint256(123)));
    }

    function test_OnlyAuthenticatedCallbackCanSettleAndCallbackCannotReplay() public {
        _commitBoth();
        _closeAndRevealBoth();
        vm.warp(settlement.getBatch(1).revealDeadline);
        settlement.closeReveal(1);

        vm.expectRevert(CommitBatch.InvalidCallback.selector);
        settlement.settleBatch(RVM_ID, 1, 1, PRICE_LIMIT);
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(CommitBatch.InvalidCallback.selector);
        settlement.settleBatch(address(0xBAD), 1, 1, PRICE_LIMIT);

        vm.prank(CALLBACK_PROXY);
        settlement.settleBatch(RVM_ID, 1, 1, PRICE_LIMIT);
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(CommitBatch.InvalidCallback.selector);
        settlement.settleBatch(RVM_ID, 1, 1, PRICE_LIMIT);
    }

    function test_MissingRevealCancelsAndBothOwnersRefund() public {
        _commitBoth();
        vm.warp(settlement.getBatch(1).commitDeadline);
        settlement.closeCommit(1);
        vm.prank(ALICE);
        settlement.reveal(aliceOrder, aliceSalt);
        vm.warp(settlement.getBatch(1).revealDeadline);
        settlement.closeReveal(1);

        assertEq(uint8(settlement.getBatch(1).phase), uint8(CommitBatch.Phase.Cancelled));
        vm.prank(ALICE);
        settlement.refund(1, aliceCommitment);
        vm.prank(BOB);
        settlement.refund(1, bobCommitment);
        assertEq(weth.balanceOf(ALICE), 10 ether);
        assertEq(usdc.balanceOf(BOB), 14_000e6);
    }

    function test_PartiallyConsumedResidualReturnsUnusedInputDuringClaim() public {
        executor.setInputUsed(2 ether);
        _commitBoth();
        _closeAndRevealBoth();
        _requestAndSettle();

        assertEq(settlement.claimable(aliceCommitment, address(weth)), 1 ether);
        vm.prank(ALICE);
        settlement.claim(1, aliceCommitment);
        assertEq(weth.balanceOf(ALICE), 1 ether);
        assertEq(usdc.balanceOf(ALICE), 19_970e6);
    }

    function test_SameDirectionAndSameOwnerCannotFillBatch() public {
        settlement.createBatch(10, 10);
        vm.prank(ALICE);
        settlement.commit(1, aliceCommitment, true, 10 ether);

        vm.prank(BOB);
        vm.expectRevert(CommitBatch.DirectionConflict.selector);
        settlement.commit(1, bobCommitment, true, 14_000e6);

        usdc.mint(ALICE, 14_000e6);
        vm.prank(ALICE);
        usdc.approve(address(settlement), type(uint256).max);
        vm.prank(ALICE);
        vm.expectRevert(CommitBatch.DuplicateOwner.selector);
        settlement.commit(1, bobCommitment, false, 14_000e6);
    }

    function test_ReadyBatchCanOnlyCancelAfterTimeout() public {
        _commitBoth();
        _closeAndRevealBoth();
        vm.warp(settlement.getBatch(1).revealDeadline);
        settlement.closeReveal(1);
        vm.expectRevert(CommitBatch.InvalidPhase.selector);
        settlement.cancelStaleBatch(1);
        vm.warp(settlement.getBatch(1).cancelAfter);
        settlement.cancelStaleBatch(1);
        assertEq(uint8(settlement.getBatch(1).phase), uint8(CommitBatch.Phase.Cancelled));
    }

    function _commitBoth() private {
        settlement.createBatch(10, 10);
        vm.prank(ALICE);
        settlement.commit(1, aliceCommitment, true, 10 ether);
        vm.prank(BOB);
        settlement.commit(1, bobCommitment, false, 14_000e6);
    }

    function _closeAndRevealBoth() private {
        vm.warp(settlement.getBatch(1).commitDeadline);
        settlement.closeCommit(1);
        vm.prank(ALICE);
        settlement.reveal(aliceOrder, aliceSalt);
        vm.prank(BOB);
        settlement.reveal(bobOrder, bobSalt);
    }

    function _requestAndSettle() private {
        vm.warp(settlement.getBatch(1).revealDeadline);
        settlement.closeReveal(1);
        vm.prank(CALLBACK_PROXY);
        settlement.settleBatch(RVM_ID, 1, 1, PRICE_LIMIT);
    }
}
