// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { CommitBatch } from "../src/core/CommitBatch.sol";
import { OrderHash } from "../src/libraries/OrderHash.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

/// @notice Runs one human-timed stage of the canonical two-wallet testnet demonstration.
contract RunDemo is Script {
    uint128 internal constant ALICE_WETH = 10 ether;
    uint128 internal constant BOB_USDC = 14_000e6;
    uint128 internal constant ALICE_MIN_USDC = 14_000e6;
    uint128 internal constant BOB_MIN_WETH = 7 ether;

    error InvalidStage();

    function run() external {
        string memory stage = vm.envString("DEMO_STAGE");
        if (keccak256(bytes(stage)) == keccak256("setup")) {
            _setup();
        } else if (keccak256(bytes(stage)) == keccak256("reveal")) {
            _reveal();
        } else if (keccak256(bytes(stage)) == keccak256("request-settlement")) {
            _requestSettlement();
        } else if (keccak256(bytes(stage)) == keccak256("claim")) {
            _claim();
        } else {
            revert InvalidStage();
        }
    }

    function _setup() private {
        (CommitBatch batch, MockERC20 weth, MockERC20 usdc) = _contracts();
        uint256 operatorKey = vm.envUint("OPERATOR_PRIVATE_KEY");
        uint256 aliceKey = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 bobKey = vm.envUint("BOB_PRIVATE_KEY");
        address alice = vm.addr(aliceKey);
        address bob = vm.addr(bobKey);
        uint64 batchId = batch.nextBatchId() + 1;
        (OrderHash.Order memory aliceOrder, OrderHash.Order memory bobOrder) = _orders(batchId, alice, bob);

        vm.startBroadcast(operatorKey);
        weth.mint(alice, ALICE_WETH);
        usdc.mint(bob, BOB_USDC);
        batch.createBatch(uint64(vm.envUint("DEMO_COMMIT_DURATION")), uint64(vm.envUint("DEMO_REVEAL_DURATION")));
        vm.stopBroadcast();

        vm.startBroadcast(aliceKey);
        weth.approve(address(batch), ALICE_WETH);
        batch.commit(batchId, OrderHash.hash(aliceOrder, vm.envBytes32("ALICE_SALT")), true, ALICE_WETH);
        vm.stopBroadcast();

        vm.startBroadcast(bobKey);
        usdc.approve(address(batch), BOB_USDC);
        batch.commit(batchId, OrderHash.hash(bobOrder, vm.envBytes32("BOB_SALT")), false, BOB_USDC);
        vm.stopBroadcast();
    }

    function _reveal() private {
        (CommitBatch batch,,) = _contracts();
        uint256 operatorKey = vm.envUint("OPERATOR_PRIVATE_KEY");
        uint256 aliceKey = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 bobKey = vm.envUint("BOB_PRIVATE_KEY");
        uint64 batchId = uint64(vm.envUint("DEMO_BATCH_ID"));
        (OrderHash.Order memory aliceOrder, OrderHash.Order memory bobOrder) =
            _orders(batchId, vm.addr(aliceKey), vm.addr(bobKey));

        vm.startBroadcast(operatorKey);
        batch.closeCommit(batchId);
        vm.stopBroadcast();

        vm.startBroadcast(aliceKey);
        batch.reveal(aliceOrder, vm.envBytes32("ALICE_SALT"));
        vm.stopBroadcast();

        vm.startBroadcast(bobKey);
        batch.reveal(bobOrder, vm.envBytes32("BOB_SALT"));
        vm.stopBroadcast();
    }

    function _requestSettlement() private {
        (CommitBatch batch,,) = _contracts();
        vm.startBroadcast(vm.envUint("OPERATOR_PRIVATE_KEY"));
        batch.closeReveal(uint64(vm.envUint("DEMO_BATCH_ID")));
        vm.stopBroadcast();
    }

    function _claim() private {
        (CommitBatch batch,,) = _contracts();
        uint256 aliceKey = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 bobKey = vm.envUint("BOB_PRIVATE_KEY");
        uint64 batchId = uint64(vm.envUint("DEMO_BATCH_ID"));
        (OrderHash.Order memory aliceOrder, OrderHash.Order memory bobOrder) =
            _orders(batchId, vm.addr(aliceKey), vm.addr(bobKey));

        vm.startBroadcast(aliceKey);
        batch.claim(batchId, OrderHash.hash(aliceOrder, vm.envBytes32("ALICE_SALT")));
        vm.stopBroadcast();

        vm.startBroadcast(bobKey);
        batch.claim(batchId, OrderHash.hash(bobOrder, vm.envBytes32("BOB_SALT")));
        vm.stopBroadcast();
    }

    function _contracts() private view returns (CommitBatch batch, MockERC20 weth, MockERC20 usdc) {
        batch = CommitBatch(vm.envAddress("COMMIT_BATCH"));
        weth = MockERC20(vm.envAddress("DEMO_WETH"));
        usdc = MockERC20(vm.envAddress("DEMO_USDC"));
    }

    function _orders(uint64 batchId, address alice, address bob)
        private
        pure
        returns (OrderHash.Order memory aliceOrder, OrderHash.Order memory bobOrder)
    {
        aliceOrder = OrderHash.Order(batchId, alice, true, ALICE_WETH, ALICE_MIN_USDC, alice, batchId);
        bobOrder = OrderHash.Order(batchId, bob, false, BOB_USDC, BOB_MIN_WETH, bob, batchId);
    }
}
