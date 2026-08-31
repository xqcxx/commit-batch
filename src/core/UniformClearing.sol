// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Pure two-sided clearing math for an 18-decimal base and configurable-decimal quote token.
library UniformClearing {
    uint256 internal constant WAD = 1e18;

    error InvalidPrice();
    error InvalidDecimals();
    error AmountOverflow();

    struct Result {
        uint128 matchedBase;
        uint128 matchedQuote;
        bool residualZeroForOne;
        uint128 residualIn;
    }

    function clear(uint128 baseIn, uint128 quoteIn, uint256 priceX18, uint8 quoteDecimals)
        internal
        pure
        returns (Result memory result)
    {
        if (priceX18 == 0) revert InvalidPrice();
        if (quoteDecimals > 18) revert InvalidDecimals();

        uint256 quoteScale = 10 ** (18 - quoteDecimals);
        uint256 quoteDemandInBase = uint256(quoteIn) * quoteScale * WAD / priceX18;
        uint256 matchedBase = uint256(baseIn) < quoteDemandInBase ? uint256(baseIn) : quoteDemandInBase;
        uint256 matchedQuote = matchedBase * priceX18 / WAD / quoteScale;

        if (matchedBase > type(uint128).max || matchedQuote > type(uint128).max) revert AmountOverflow();
        result.matchedBase = uint128(matchedBase);
        result.matchedQuote = uint128(matchedQuote);

        if (uint256(baseIn) > matchedBase) {
            result.residualZeroForOne = true;
            result.residualIn = uint128(uint256(baseIn) - matchedBase);
        } else if (uint256(quoteIn) > matchedQuote) {
            result.residualZeroForOne = false;
            result.residualIn = uint128(uint256(quoteIn) - matchedQuote);
        }
    }

    function quoteForBase(uint256 baseAmount, uint256 priceX18, uint8 quoteDecimals) internal pure returns (uint256) {
        if (priceX18 == 0) revert InvalidPrice();
        if (quoteDecimals > 18) revert InvalidDecimals();
        return baseAmount * priceX18 / WAD / (10 ** (18 - quoteDecimals));
    }

    function baseForQuote(uint256 quoteAmount, uint256 priceX18, uint8 quoteDecimals) internal pure returns (uint256) {
        if (priceX18 == 0) revert InvalidPrice();
        if (quoteDecimals > 18) revert InvalidDecimals();
        return quoteAmount * (10 ** (18 - quoteDecimals)) * WAD / priceX18;
    }
}
