// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { CommitBatch } from "../src/core/CommitBatch.sol";

/// @notice One-time wiring after a Lasna RSC has been deployed and its RVM identity is known.
contract ConfigureReactiveIntegration is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        CommitBatch batch = CommitBatch(vm.envAddress("COMMIT_BATCH"));
        address router = vm.envAddress("COMMIT_BATCH_ROUTER");
        address hook = vm.envAddress("COMMIT_BATCH_HOOK");
        address rvmId = vm.envAddress("EXPECTED_RVM_ID");
        vm.startBroadcast(privateKey);
        batch.configureIntegrations(router, hook, rvmId);
        vm.stopBroadcast();
    }
}
