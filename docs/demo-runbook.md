# Demo Runbook

## Goal

Show the fixture implemented by the lifecycle test at controlled `priceX18 = 2_000e18`:

- Alice escrows and reveals `10 WETH` base-to-quote.
- Bob escrows and reveals `14,000 USDC` quote-to-base.
- `7 WETH` and `14,000 USDC` match at the captured price.
- The computed `3 WETH` residual is requested through the v4 router and hook.
- Bob claims `7 WETH`; Alice claims `14,000 USDC` plus actual residual output.

The deterministic mock-executor test returns `5,970 USDC`, so Alice claims `19,970 USDC` in that test. A real v4 run has pool-dependent output; do not promise `5,970 USDC` or full residual consumption without transaction evidence.

## Timing

The spoken script is 4 minutes 30 seconds. Use already-confirmed transactions or a recording and move immediately to event evidence if network latency would push the presentation past five minutes.

## Pre-Demo Checklist

- `CommitBatch`, `CommitBatchRouter`, `CommitBatchHook`, and `CommitBatchRSC` addresses are open.
- `MockReferencePrice.priceX18()` reads `2_000e18`; identify it as owner-controlled demo infrastructure.
- `CommitBatch` shows the intended tokens, six quote decimals, Callback Proxy, router, hook, and expected RVM ID.
- The RSC filters the exact `CommitBatch` and has the intended callback gas and `sqrtPriceLimitX96`.
- Alice has `10 WETH`; Bob has `14,000 USDC`; allowances target `CommitBatch`.
- The pool has enough liquidity and the chosen price limit is expected to consume all `3 WETH`.
- Both exact seven-field `Order` values and salts are retained locally.
- Use fresh batch IDs and salts for every live rehearsal or recording. A confirmed prior run is useful as fallback evidence if testnet latency interrupts the recording.

## Procedure

### 1. Commit

Show or submit both commitments and deposits. Explain that the hash binds `batchId`, owner, direction, `amountIn`, `minAmountOut`, recipient, nonce, and salt. There is no order `limitPriceX96` field.

Point out that this is not private: `commit` calldata includes direction and amount, transfers are public, and `getCommitment` exposes stored data. Only the `OrderCommitted` event omits explicit direction and amount.

### 2. Snapshot And Reveal

At or after `commitDeadline`, call `closeCommit`. Show phase `Reveal` and `clearingPriceX18 = 2_000e18`.

Reveal both orders before `revealDeadline`. Eligibility means each full input's reference output is at least its `minAmountOut`. No separate order price test exists.

### 3. Request Settlement

At or after `revealDeadline`, call `closeReveal`. Show phase `Ready` and `SettlementRequested(batchId, callbackNonce)`.

Trace the RSC callback payload:

```text
settleBatch(rvmId, batchId, callbackNonce, sqrtPriceLimitX96)
```

Show that the destination transaction sender is the Callback Proxy and `rvmId` is the configured RSC identity.

### 4. Verify Match And Residual

Show contract/event values:

```text
matchedBase:  7 WETH
matchedQuote: 14,000 USDC
residualIn:   3 WETH, base-to-quote
residualOut:  actual router output
```

The hook validates and consumes the exact one-time authorization in `beforeSwap`. The router performs the swap and reports actual output. Do not say the hook has `afterSwap` accounting or permits an arbitrary smaller request.

### 5. Claim

Have Bob, the order owner, call `claim` and show `7 WETH` sent to Bob's hash-bound recipient. Have Alice call `claim` and show `14,000 USDC + residualOut` sent to Alice's recipient. If a price limit used less than `3 WETH`, the same claim also returns Alice's unused WETH. Claims are keyed by commitment and can execute only once.

### 6. Limits

Show tested evidence for invalid salt, unauthenticated/wrong-RVM callback, replay, missing-reveal cancellation/refunds, owner/direction restrictions, and cancellation timing.

State untested or unresolved limitations accurately:

- residual MEV and pool dependence remain;
- `cancelAfter` enables cancellation but does not itself block settlement;
- residual price-limit output is pool-dependent; an unused partial input is returned as a pull credit;
- the mock price is not production-safe; and
- current tests are not a comprehensive audit or conservation proof.

## Failure Handling

| Symptom | Action |
| --- | --- |
| Reveal mismatch | Verify wallet, batch, all seven order fields, ABI encoding, and salt |
| Batch cancels at reveal close | One or both orders were absent, unrevealed, or reference-ineligible; owners call `refund` |
| No Reactive callback | Check event chain/emitter/topic, RSC funding, destination, and gas |
| Callback reverts | Check Callback Proxy, RVM ID, phase, nonce, integration wiring, and residual path |
| Residual reverts | Check pool key, liquidity, direction mapping, authorization, price limit, and both `minAmountOut` values |
| Stale `Ready` batch | Call `cancelStaleBatch` at/after `cancelAfter`; recognize a callback can win before cancellation mines |

Never change the captured price, impersonate Reactive, weaken claims, or present manually altered state as successful execution.
