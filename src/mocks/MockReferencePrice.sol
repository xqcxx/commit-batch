// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IReferencePrice } from "../interfaces/IReferencePrice.sol";

/// @notice Controlled mechanism-demo source. This is not a production oracle.
contract MockReferencePrice is IReferencePrice {
    address public immutable owner;
    uint256 public priceX18;

    error Unauthorized();
    error InvalidPrice();

    constructor(address owner_, uint256 initialPriceX18) {
        if (owner_ == address(0) || initialPriceX18 == 0) revert InvalidPrice();
        owner = owner_;
        priceX18 = initialPriceX18;
    }

    function setPrice(uint256 nextPriceX18) external {
        if (msg.sender != owner) revert Unauthorized();
        if (nextPriceX18 == 0) revert InvalidPrice();
        priceX18 = nextPriceX18;
        emit PriceUpdated(nextPriceX18);
    }

    event PriceUpdated(uint256 priceX18);
}
