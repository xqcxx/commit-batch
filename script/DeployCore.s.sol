// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { CommitBatch } from "../src/core/CommitBatch.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockReferencePrice } from "../src/mocks/MockReferencePrice.sol";

/// @notice Deploys the pair-independent CommitBatch core for local or testnet setup.
/// @dev v4 hook deployment is separate because its CREATE2 address must encode hook permissions.
contract DeployCore is Script {
    uint256 internal constant DEMO_PRICE_X18 = 2_000e18;

    function run() external returns (MockERC20 weth, MockERC20 usdc, MockReferencePrice price, CommitBatch batch) {
        address callbackProxy = vm.envAddress("CALLBACK_PROXY");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);
        weth = new MockERC20("Demo Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("Demo USD Coin", "USDC", 6);
        price = new MockReferencePrice(deployer, DEMO_PRICE_X18);
        batch = new CommitBatch(deployer, address(weth), address(usdc), 6, price, callbackProxy, 30 minutes);
        vm.stopBroadcast();
    }
}
