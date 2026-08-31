// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { CommitBatch } from "../src/core/CommitBatch.sol";
import { CommitBatchHook, ICommitBatchAuthorization } from "../src/hook/CommitBatchHook.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockReferencePrice } from "../src/mocks/MockReferencePrice.sol";
import { CommitBatchHookFactory } from "../src/deploy/CommitBatchHookFactory.sol";
import { CommitBatchRouter } from "../src/v4/CommitBatchRouter.sol";
import { CommitBatchLiquiditySeeder } from "../src/v4/CommitBatchLiquiditySeeder.sol";

/// @notice Deploys and seeds the complete Unichain half of the testnet demonstration.
/// @dev Run DeployRSC on Lasna next, then ConfigureReactiveIntegration back on Unichain.
contract DeployUnichainDemo is Script {
    uint256 internal constant DEMO_PRICE_X18 = 2_000e18;
    uint128 internal constant DEMO_LIQUIDITY = 1e24;
    uint256 internal constant DEMO_MINT = 1e30;
    uint24 internal constant POOL_FEE = 3_000;
    int24 internal constant TICK_SPACING = 60;
    uint160 internal constant ALL_HOOK_MASK = (1 << 14) - 1;
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;

    error HookSaltNotFound();

    event UnichainDemoDeployed(
        address indexed commitBatch,
        address indexed router,
        address indexed hook,
        address baseToken,
        address quoteToken,
        address referencePrice,
        address liquiditySeeder,
        bytes32 hookSalt
    );

    function run()
        external
        returns (
            CommitBatch batch,
            CommitBatchRouter router,
            CommitBatchHook hook,
            MockERC20 weth,
            MockERC20 usdc,
            MockReferencePrice price
        )
    {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        IPoolManager poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address callbackProxy = vm.envAddress("CALLBACK_PROXY");

        vm.startBroadcast(privateKey);
        weth = new MockERC20("Demo Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("Demo USD Coin", "USDC", 6);
        price = new MockReferencePrice(deployer, DEMO_PRICE_X18);
        batch = new CommitBatch(deployer, address(weth), address(usdc), 6, price, callbackProxy, 30 minutes);
        router = new CommitBatchRouter(poolManager, address(batch), address(weth), address(usdc));
        CommitBatchHookFactory factory = new CommitBatchHookFactory();
        vm.stopBroadcast();

        bytes32 creationHash = factory.initCodeHash(
            poolManager, ICommitBatchAuthorization(address(batch)), address(router), address(weth), address(usdc)
        );
        bytes32 hookSalt = _mineHookSalt(address(factory), creationHash, 200_000);
        vm.startBroadcast(privateKey);
        hook = factory.deploy(
            hookSalt,
            poolManager,
            ICommitBatchAuthorization(address(batch)),
            address(router),
            address(weth),
            address(usdc)
        );
        PoolKey memory key = _poolKey(weth, usdc, hook);
        router.configurePool(key);
        poolManager.initialize(key, _sqrtPriceX96(key, address(weth), address(usdc)));
        CommitBatchLiquiditySeeder seeder = new CommitBatchLiquiditySeeder(poolManager, key, deployer);
        weth.mint(deployer, DEMO_MINT);
        usdc.mint(deployer, DEMO_MINT);
        weth.approve(address(seeder), type(uint256).max);
        usdc.approve(address(seeder), type(uint256).max);
        seeder.seed(DEMO_LIQUIDITY);
        vm.stopBroadcast();

        emit UnichainDemoDeployed(
            address(batch),
            address(router),
            address(hook),
            address(weth),
            address(usdc),
            address(price),
            address(seeder),
            hookSalt
        );
    }

    function _poolKey(MockERC20 weth, MockERC20 usdc, CommitBatchHook hook) private pure returns (PoolKey memory) {
        (address currency0, address currency1) =
            address(weth) < address(usdc) ? (address(weth), address(usdc)) : (address(usdc), address(weth));
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
    }

    function _sqrtPriceX96(PoolKey memory key, address baseToken, address) private pure returns (uint160) {
        uint256 q192 = uint256(1) << 192;
        bool baseIsCurrency0 = Currency.unwrap(key.currency0) == baseToken;
        uint256 ratioX192 =
            baseIsCurrency0 ? (q192 / 1e18) * DEMO_PRICE_X18 / 1e12 : q192 * (1e36 / (DEMO_PRICE_X18 * 1e6));
        return uint160(_sqrt(ratioX192));
    }

    function _sqrt(uint256 value) private pure returns (uint256 result) {
        if (value == 0) return 0;
        uint256 z = (value + 1) / 2;
        result = value;
        while (z < result) {
            result = z;
            z = (value / z + z) / 2;
        }
    }

    function _mineHookSalt(address factory, bytes32 creationHash, uint256 iterations)
        private
        pure
        returns (bytes32 salt)
    {
        for (uint256 candidate; candidate < iterations; ++candidate) {
            salt = bytes32(candidate);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factory, salt, creationHash)))));
            if ((uint160(predicted) & ALL_HOOK_MASK) == BEFORE_SWAP_FLAG) return salt;
        }
        revert HookSaltNotFound();
    }
}
