// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IReferencePrice {
    /// @return priceX18 Quote-token value of one whole base token, normalized to 18 decimals.
    function priceX18() external view returns (uint256 priceX18);
}
