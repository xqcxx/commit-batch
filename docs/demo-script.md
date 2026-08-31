# CommitBatch Demo Script

**Target runtime: 4 minutes 30 seconds.** This is a concise narration companion to the operational [partner recording guide](../script.md). Use confirmed transactions or switch to a recorded event trace rather than waiting for testnet confirmations if a short-format recording cannot absorb testnet latency.

## 0:00-0:35 | Claim

"Two public AMM swaps execute sequentially even when opposing flow could match. CommitBatch binds two opposite exact-input orders, matches compatible flow at one captured price, and sends only the computed imbalance to Uniswap v4. It reduces gross pool interaction; it does not remove all MEV."

Show Alice selling `10 WETH` and Bob selling `14,000 USDC` at the controlled `2,000 USDC/WETH` reference price.

## 0:35-1:10 | Binding, Not Privacy

Show both commitments and escrow transfers.

"The hash binds batch ID, owner, direction, input, minimum output, recipient, nonce, and salt. There is no per-order price-limit field. This is binding, not private: commit calldata, token transfers, and the commitment getter expose direction and size even though the event itself omits them."

## 1:10-1:45 | Snapshot And Reveal

Show `closeCommit`, phase `Reveal`, and `clearingPriceX18 = 2_000e18`, then both reveals.

"At commit close, `CommitBatch` snapshots the owner-controlled `MockReferencePrice`. It is reproducible demo input, not a production oracle. Each reveal must reproduce its hash, deposit, owner, direction, recipient, and unused nonce. Its reference output must meet `minAmountOut`."

## 1:45-2:30 | Reactive Callback

Show `closeReveal`, `SettlementRequested`, the RSC trace, and destination callback.

"With exactly two eligible reveals, phase becomes `Ready`. The RSC filters this contract's event and asks the Callback Proxy to call `settleBatch` with RVM ID, batch ID, callback nonce, and the RSC's fixed square-root price limit. `CommitBatch` checks proxy, RVM ID, phase, and nonce."

Show `BatchSettled`; mention that replay fails because the phase is no longer `Ready`.

## 2:30-3:20 | Net First, AMM Second

Show `InternalFlowMatched`, `ResidualAuthorized`, `ResidualAuthorizationConsumed`, and `ResidualExecuted`.

"The formula matches `7 WETH` with `14,000 USDC`. Alice's computed `3 WETH` residual is authorized once. The hook validates the exact request in `beforeSwap`; the router executes through PoolManager and returns actual output. Matched flow uses the captured price. Residual output uses pool state, fees, and the v4 price limit."

"Residual MEV remains. If the v4 price limit partially consumes a residual, the router reports actual input used and the unused input becomes a second pull credit for that trader."

## 3:20-3:55 | Claims

Show Bob's `7 WETH` credit and Alice's `14,000 USDC + residualOut`, then claims.

"Claims are pull-based: only each order owner can call, and output goes to the committed recipient. The mock lifecycle test returns `5,970 USDC` for the residual and Alice claims `19,970 USDC`; a real v4 result is not fixed."

## 3:55-4:30 | Limits

Show current test output.

"Tests cover bad salt, callback authentication and replay, missing-reveal refunds, pair restrictions, stale cancellation timing, RSC filtering, clearing invariants, and a real PoolManager/hook path. This does not prove privacy, production oracle safety, optimal execution, or elimination of residual MEV."

"`cancelAfter` makes a `Ready` batch cancellable; it is not a hard callback deadline. Until cancellation is mined, an authenticated callback can still settle. The mechanism is narrow and demonstrable, with those limitations explicit."
