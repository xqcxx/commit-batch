---
marp: true
title: CommitBatch
description: Commitment-bound two-order matching with residual-only Uniswap v4 execution
paginate: true
---

# CommitBatch

## Net first. AMM second.

One `CommitBatch` contract escrows, matches, settles, credits, and refunds.

---

# Reduce gross pool flow

**Sequential route**

1. Alice's public exact-input swap moves the pool.
2. Bob's opposing public swap executes afterward.
3. Ordering and residual sandwich opportunities remain.

**CommitBatch route**

- Two opposite orders are bound before reveal.
- Compatible flow matches under one formula and snapshot.
- Only the computed imbalance is requested from v4.

> Matched flow loses individual execution order. Residual MEV remains.

---

# Binding, not private

```text
commitment = keccak256(abi.encode(order, salt))
```

The seven-field order binds:

`batchId + owner + direction + amountIn + minAmountOut + recipient + nonce`

- No `limitPriceX96` order field.
- `commit` calldata, transfers, and `getCommitment` expose direction and amount.
- The `OrderCommitted` event itself contains only batch, hash, and owner.

---

# Implemented contracts

| Contract/library | Role |
| --- | --- |
| `CommitBatch` | Phases, escrow, snapshot, settlement, credits, refunds |
| `UniformClearing` | Pure two-sided integer math |
| `CommitBatchRSC` | Event filter and Reactive callback request |
| `CommitBatchRouter` | PoolManager unlock, swap, delta settlement, output |
| `CommitBatchHook` | `beforeSwap` authorization consumption |
| `MockReferencePrice` | Owner-controlled demo `priceX18` source |

No vault/controller split. No solver network. No production oracle claim.

---

# Exact lifecycle

```text
None
  v createBatch
Commit -- closeCommit/deadline --> Reveal
                                  |
                     closeReveal  | exactly two eligible
                                  v
                                Ready -- callback --> Settled
                                  |
                                  +-- cancelStaleBatch --> Cancelled

Reveal -- missing/unrevealed/ineligible --> Cancelled
```

`cancelAfter` enables cancellation. It does not make settlement expire automatically.

---

# Controlled price and formula

Captured demo price: **`2_000e18` = 2,000 USDC/WETH**

```text
S = 10^(18 - quoteDecimals)
quoteDemandInBase = floor(quoteIn * S * 1e18 / priceX18)
matchedBase       = min(baseIn, quoteDemandInBase)
matchedQuote      = floor(matchedBase * priceX18 / 1e18 / S)
```

- Base is assumed 18 decimals; quote decimals are configured.
- Solidity checked arithmetic; no full-precision `mulDiv`.
- Eligibility and final settlement each enforce `minAmountOut`.

---

# Canonical fixture

```text
Alice input: 10 WETH
Bob input:   14,000 USDC

matched:     7 WETH <-> 14,000 USDC
residual:    3 WETH base-to-quote through v4
```

- Bob credit: `7 WETH`.
- Alice credit: `14,000 USDC + actual residualOut`.
- Mock lifecycle test residual: `5,970 USDC`.
- Real-v4 output: pool-dependent, tested only as positive.

---

# Residual authorization

`CommitBatch` binds one active authorization to:

- batch ID and fresh residual nonce;
- protocol direction;
- exact computed requested input; and
- callback-supplied `sqrtPriceLimitX96`.

The hook consumes it in `beforeSwap`. The router maps currency order, executes, settles actual deltas, and returns output.

If the price limit causes partial input consumption, the router returns actual input used and the unused input becomes a pull credit for the residual owner.

---

# Exact Reactive callback

```text
SettlementRequested(uint64 batchId, uint64 callbackNonce)
                         |
                         v
CommitBatchRSC filters chain + emitter + topic
                         |
                         v
settleBatch(
  address rvmId,
  uint64 batchId,
  uint64 callbackNonce,
  uint160 sqrtPriceLimitX96
)
```

Destination checks Callback Proxy, expected RVM ID, `Ready`, and nonce.

---

# What is actually demonstrated

**Covered by current tests**

- canonical and quote-long clearing plus a bounded fuzz invariant;
- full mock-executor lifecycle and pull claims;
- bad salt, callback authentication/replay, and stale cancellation;
- RSC filtering/dedup state; and
- one real PoolManager/router/hook residual path.

**Not proven**

- privacy, censorship resistance, or production oracle safety;
- hard settlement expiry at `cancelAfter`;
- broad conservation across decimal and price-limit boundaries;
- optimal execution or elimination of residual MEV; or
- production readiness/audit status.

## Net first. Bound the rest. State the limits.
