// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { CommitBatchHook, ICommitBatchAuthorization } from "../hook/CommitBatchHook.sol";

/// @notice Mines and deploys a CREATE2 hook whose low address bits encode `beforeSwap` permission.
contract CommitBatchHookFactory {
    uint160 internal constant ALL_HOOK_MASK = (1 << 14) - 1;
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;

    error SaltNotFound();
    event HookDeployed(address indexed hook, bytes32 indexed salt);

    function findSalt(
        IPoolManager poolManager,
        ICommitBatchAuthorization settlement,
        address router,
        address baseToken,
        address quoteToken,
        uint256 start,
        uint256 iterations
    ) external view returns (bytes32 salt, address predicted) {
        bytes32 creationHash = initCodeHash(poolManager, settlement, router, baseToken, quoteToken);
        for (uint256 candidate = start; candidate < start + iterations; ++candidate) {
            salt = bytes32(candidate);
            predicted = computeAddress(salt, creationHash);
            if ((uint160(predicted) & ALL_HOOK_MASK) == BEFORE_SWAP_FLAG) return (salt, predicted);
        }
        revert SaltNotFound();
    }

    function deploy(
        bytes32 salt,
        IPoolManager poolManager,
        ICommitBatchAuthorization settlement,
        address router,
        address baseToken,
        address quoteToken
    ) external returns (CommitBatchHook hook) {
        hook = new CommitBatchHook{ salt: salt }(poolManager, settlement, router, baseToken, quoteToken);
        emit HookDeployed(address(hook), salt);
    }

    function initCodeHash(
        IPoolManager poolManager,
        ICommitBatchAuthorization settlement,
        address router,
        address baseToken,
        address quoteToken
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                type(CommitBatchHook).creationCode, abi.encode(poolManager, settlement, router, baseToken, quoteToken)
            )
        );
    }

    function computeAddress(bytes32 salt, bytes32 creationHash) public view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, creationHash)))));
    }
}
