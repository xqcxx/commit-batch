// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IResidualExecutor {
    function executeResidual(
        uint64 batchId,
        uint64 authorizationNonce,
        bool zeroForOne,
        uint128 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountInUsed, uint256 amountOut);
}
