# Two-Order Clearing Rule

## Scope

Each settled batch has exactly two revealed, eligible exact-input orders: one sells base for quote and one sells quote for base. Matched amounts use one captured reference price. At most one unmatched input amount is requested as a Uniswap v4 residual swap.

## Representation

- Base is assumed to have 18 decimals.
- Quote has immutable `quoteDecimals <= 18`.
- `priceX18` is the whole-quote-token value of one whole base token, normalized to 18 decimals.
- `quoteScale = 10 ** (18 - quoteDecimals)`.
- `zeroForOne = true` means base-to-quote at the protocol layer, independent of v4 currency ordering.

For WETH base and six-decimal USDC quote, `2,000 USDC/WETH` is encoded as `2_000e18`, not as a Q96 value. `closeCommit` reads `IReferencePrice.priceX18()` once and stores it in `Batch.clearingPriceX18`.

## Order And Eligibility

The hash binds this exact order and a salt:

```solidity
Order(
    uint64 batchId,
    address owner,
    bool zeroForOne,
    uint128 amountIn,
    uint128 minAmountOut,
    address recipient,
    uint64 nonce
)
```

There is no order price-limit field. During reveal, the code computes:

```text
base seller reference output  = floor(amountIn * priceX18 / 1e18 / quoteScale)
quote seller reference output = floor(amountIn * quoteScale * 1e18 / priceX18)
eligible                      = reference output >= minAmountOut
```

If either commitment is absent, unrevealed, or ineligible, `closeReveal` changes the entire batch to `Cancelled`; both owners may refund their full deposits. The implementation never settles a one-sided or partially eligible batch.

## Matching Formula

Given base input `B`, quote input `Q`, captured price `P`, and scale `S`:

```text
quoteDemandInBase = floor(Q * S * 1e18 / P)
matchedBase       = min(B, quoteDemandInBase)
matchedQuote      = floor(matchedBase * P / 1e18 / S)
```

Residual selection is exactly:

```text
if B > matchedBase:
    residualZeroForOne = true
    residualIn = B - matchedBase
else if Q > matchedQuote:
    residualZeroForOne = false
    residualIn = Q - matchedQuote
else:
    residualIn = 0
```

All divisions floor. Solidity 0.8 checked arithmetic reverts on intermediate overflow. The current library does not use 512-bit `mulDiv`, so documentation and integrations must not claim full-domain overflow resistance.

## Allocation And Final Minimums

Before residual output:

```text
base seller receives  matchedQuote
quote seller receives matchedBase
```

If base is residual, its actual quote output is added to the base seller's output. If quote is residual, its actual base output is added to the quote seller's output. Settlement then enforces:

```text
base seller total quote output >= base seller minAmountOut
quote seller total base output >= quote seller minAmountOut
```

Failure reverts the whole settlement, including authorization consumption and pool swap.

## Residual Semantics

`CommitBatch` authorizes exactly the computed `residualIn`, direction, batch ID, fresh residual nonce, and callback-supplied `sqrtPriceLimitX96`. The hook validates the exact requested amount and consumes this authorization once. The router submits a negative `amountSpecified`, so the v4 request is exact input, and returns actual positive output.

`Batch.residualIn` records the computed/requested residual. `Batch.residualOut` records actual router output. The residual does not clear at `clearingPriceX18`; pool state, fees, and the square-root price limit determine its output.

The router returns both the PoolManager's actual negative input delta and its positive output delta. If a price limit partially consumes a residual, `CommitBatch` credits the unused input token alongside that order's normal output. `claim` transfers both credits atomically to the committed recipient. The protocol never treats a requested residual amount as if it were necessarily fully consumed.

## Canonical Fixture

At `P = 2_000e18`, with WETH base and six-decimal USDC quote:

```text
B = 10e18 WETH units
Q = 14_000e6 USDC units
S = 1e12

quoteDemandInBase = 7e18
matchedBase       = 7e18
matchedQuote      = 14_000e6
residual          = 3e18 base, base-to-quote
```

Bob's credit is `7 WETH`. Alice's credit is `14,000 USDC + actual router output`. The integration fixture configures mock residual output as `5,970 USDC`, producing Alice's tested claim of `19,970 USDC`. The real-v4 test only asserts positive residual output, not that fixed amount or a production-market result.

## Tested Coverage

- Canonical 18/6 decimal fixture: `7 WETH` matched and `3 WETH` residual.
- Quote-long fixture: `5 WETH`, `10,000 USDC` matched and `4,000 USDC` residual.
- Fuzz invariant: matching does not exceed either input, and the selected residual reconstructs its side's input.
- Lifecycle: invalid salt, callback authentication/replay, cancellation for a missing reveal, owner/direction restrictions, stale cancellation, pull claims, and unused-residual return.
- Real PoolManager/hook path with 18/18 mock tokens and positive residual output.

Balanced inputs, broad decimal combinations, arithmetic boundaries, partial price-limit fills against a real v4 price limit, and comprehensive token-conservation properties are not currently demonstrated by the test suite.
