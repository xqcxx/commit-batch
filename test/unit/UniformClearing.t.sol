// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { UniformClearing } from "../../src/core/UniformClearing.sol";

contract ClearingHarness {
    function clear(uint128 baseIn, uint128 quoteIn, uint256 priceX18, uint8 quoteDecimals)
        external
        pure
        returns (UniformClearing.Result memory)
    {
        return UniformClearing.clear(baseIn, quoteIn, priceX18, quoteDecimals);
    }
}

contract UniformClearingTest is Test {
    ClearingHarness private harness;

    function setUp() public {
        harness = new ClearingHarness();
    }

    function test_CanonicalScenarioMatchesSevenAndLeavesThree() public view {
        UniformClearing.Result memory result = harness.clear(10 ether, 14_000e6, 2_000e18, 6);
        assertEq(result.matchedBase, 7 ether);
        assertEq(result.matchedQuote, 14_000e6);
        assertTrue(result.residualZeroForOne);
        assertEq(result.residualIn, 3 ether);
    }

    function test_QuoteResidualUsesOppositeDirection() public view {
        UniformClearing.Result memory result = harness.clear(5 ether, 14_000e6, 2_000e18, 6);
        assertEq(result.matchedBase, 5 ether);
        assertEq(result.matchedQuote, 10_000e6);
        assertFalse(result.residualZeroForOne);
        assertEq(result.residualIn, 4_000e6);
    }

    function testFuzz_ResultNeverMatchesMoreThanEitherInput(uint96 baseIn, uint96 quoteIn, uint128 price) public view {
        baseIn = uint96(bound(baseIn, 1, 1e28));
        quoteIn = uint96(bound(quoteIn, 1, 1e20));
        price = uint128(bound(price, 1e15, 1e25));
        UniformClearing.Result memory result = harness.clear(baseIn, quoteIn, price, 6);

        assertLe(result.matchedBase, baseIn);
        assertLe(result.matchedQuote, quoteIn);
        if (result.residualZeroForOne) assertEq(uint256(result.matchedBase) + result.residualIn, baseIn);
        else assertEq(uint256(result.matchedQuote) + result.residualIn, quoteIn);
    }
}
