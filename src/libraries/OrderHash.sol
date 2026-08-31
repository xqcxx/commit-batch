// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library OrderHash {
    struct Order {
        uint64 batchId;
        address owner;
        bool zeroForOne;
        uint128 amountIn;
        uint128 minAmountOut;
        address recipient;
        uint64 nonce;
    }

    function hash(Order memory order, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(order, salt));
    }
}
