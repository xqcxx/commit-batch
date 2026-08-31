// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { CommitBatchRSC } from "../src/reactive/CommitBatchRSC.sol";

/// @notice Deploy on Reactive Lasna after the Unichain settlement address is known.
contract DeployRSC is Script {
    function run() external returns (CommitBatchRSC rsc) {
        uint256 originChainId = vm.envUint("ORIGIN_CHAIN_ID");
        uint256 destinationChainId = vm.envUint("DESTINATION_CHAIN_ID");
        address settlement = vm.envAddress("COMMIT_BATCH");
        uint64 callbackGasLimit = uint64(vm.envUint("CALLBACK_GAS_LIMIT"));
        uint160 sqrtPriceLimitX96 = uint160(vm.envUint("SQRT_PRICE_LIMIT_X96"));
        uint256 deploymentValue = vm.envOr("RSC_DEPLOYMENT_VALUE", uint256(0.01 ether));
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        rsc = new CommitBatchRSC{ value: deploymentValue }(
            originChainId, destinationChainId, settlement, settlement, callbackGasLimit, sqrtPriceLimitX96
        );
        vm.stopBroadcast();
    }
}
