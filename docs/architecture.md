# CommitBatch Architecture

## Purpose

CommitBatch is a two-order execution mechanism for one configured base/quote pair. Each batch accepts at most two exact-input commitments from different owners, and the second commitment must oppose the first. Orders are escrowed at commit, revealed after a reference-price snapshot, matched at that price, and any net input is sent through one Uniswap v4 swap.

The commitment is binding, not private. `commit` calldata contains direction and deposit amount, token transfers are public, and `getCommitment` exposes the stored commitment. The `OrderCommitted` event itself contains only batch ID, hash, and owner. Protection comes from delayed matching, not secrecy.

## Implemented Scope

| Property | Implementation |
| --- | --- |
| Settlement | One `CommitBatch` contract owns phases, escrow, matching, credits, and refunds |
| Pair | Immutable `baseToken` and `quoteToken`; clearing assumes 18-decimal base and configured quote decimals up to 18 |
| Batches | `createBatch` can create multiple batches; no single-active-batch restriction |
| Orders | At most two commitments, different owners, opposite directions, exact input |
| Price source | Immutable `IReferencePrice`; `priceX18()` is captured by `closeCommit` |
| Matched execution | `UniformClearing` at the captured price |
| Residual execution | Zero or one authorized v4 exact-input request; actual v4 output is credited |
| Fees | No protocol fee; v4 pool fee affects residual output |
| Recovery | Pull refund after cancellation |

## Topology

```text
Trader -- commit/reveal/claim/refund --> CommitBatch
                                            |
                                            | SettlementRequested(batchId, callbackNonce)
                                            v
                                      CommitBatchRSC
                                            |
                                            | Reactive Callback Proxy calls
                                            | settleBatch(rvmId, batchId,
                                            |             callbackNonce, sqrtPriceLimitX96)
                                            v
                                       CommitBatch
                                            |
                                            | computed residual only
                                            v
                                   CommitBatchRouter
                                            |
                                            | PoolManager.swap + hookData
                                            v
                                      Uniswap v4
                                            ^
                                            |
                                  CommitBatchHook consumes
                                  the exact authorization
```

## Components

### `CommitBatch`

`CommitBatch` is the only escrow and settlement contract. It creates batches, stores up to two commitments, snapshots the price, verifies reveals, requests Reactive settlement, computes and executes matching, records claim credits, and permits refunds for cancelled batches.

The exact commitment preimage is:

```solidity
struct Order {
    uint64 batchId;
    address owner;
    bool zeroForOne;
    uint128 amountIn;
    uint128 minAmountOut;
    address recipient;
    uint64 nonce;
}

bytes32 commitment = keccak256(abi.encode(order, salt));
```

There is no order-level `limitPriceX96`. The reveal is eligible when the full input converted at the captured reference price is at least `minAmountOut`. Settlement checks each order's final total output against `minAmountOut` again.

`configureIntegrations(router, hook, rvmId)` is owner-only and one-time. It records the router, hook, and expected RVM ID and gives the router unlimited allowance for both configured tokens.

### `UniformClearing`

`UniformClearing` is a pure library. It assumes base has 18 decimals, supports quote decimals up to 18, and returns `matchedBase`, `matchedQuote`, residual direction, and residual input. It performs Solidity checked arithmetic with integer division; it does not use a full-precision `mulDiv` implementation.

### `CommitBatchRouter`

The router accepts `executeResidual(batchId, authorizationNonce, zeroForOne, amountIn, sqrtPriceLimitX96)` only from `CommitBatch`. It maps protocol direction, where `zeroForOne` means base-to-quote, to the pool's currency ordering. During the PoolManager unlock callback it requests a v4 exact-input swap, settles actual negative deltas from `CommitBatch`, takes positive deltas back to `CommitBatch`, and returns both actual input used and actual output.

### `CommitBatchHook`

The hook implements only `beforeSwap`. It requires the configured router, the configured token pair, negative exact-input `amountSpecified`, the authorized direction and requested amount, and the authorized `sqrtPriceLimitX96`. It then calls:

```solidity
consumeResidualAuthorization(
    callbackSender,
    batchId,
    nonce,
    zeroForOne,
    amountIn,
    sqrtPriceLimitX96
)
```

The authorization is consumed before the swap. Output accounting is performed by `CommitBatchRouter`, not an `afterSwap` hook.

### `CommitBatchRSC`

The RSC subscribes to `SettlementRequested(uint64,uint64)` from the configured origin chain and `CommitBatch` address. `react` ignores logs with a different chain, emitter, or topic and deduplicates accepted logs by `(chain_id, tx_hash, log_index)`. It emits a Reactive callback carrying:

```solidity
settleBatch(address rvmId, uint64 batchId, uint64 callbackNonce, uint160 sqrtPriceLimitX96)
```

The RSC emits its own address as the placeholder `rvmId` and its fixed `sqrtPriceLimitX96`. Reactive replaces the callback payload's first address argument with the ReactVM ID, which is the Lasna RSC deployer's address. `CommitBatch` authenticates the Callback Proxy, that expected RVM ID, `Ready` phase, and callback nonce.

## Lifecycle

The enum is exactly:

```text
None -> Commit -> Reveal -> Ready -> Settled
                              |
                              +-----------> Cancelled

Reveal -- incomplete or ineligible pair --> Cancelled
```

1. `createBatch(commitDuration, revealDuration)` creates `Commit`, with `commitDeadline`, `revealDeadline`, and `cancelAfter = revealDeadline + cancellationDelay`.
2. `commit` escrows input before `commitDeadline`. A second commitment must use the opposite direction and a different owner.
3. `closeCommit` is permissionless at or after `commitDeadline`; it captures `referencePrice.priceX18()` and enters `Reveal`.
4. `reveal` verifies the hash, owner, direction, deposit, recipient, and unused owner nonce before `revealDeadline`.
5. `closeReveal` is permissionless at or after `revealDeadline`. Unless exactly two commitments were both revealed and eligible, it cancels the batch. Otherwise it enters `Ready`, allocates a callback nonce, and emits `SettlementRequested`.
6. An authenticated callback calls `settleBatch`. Matching and the optional residual swap occur atomically; outputs become pull-based credits and phase becomes `Settled`.
7. Owners call `claim`; output is transferred to each hash-bound recipient. For `Cancelled`, owners call `refund` to recover full deposited input.
8. `cancelStaleBatch` can move a `Ready` batch to `Cancelled` at or after `cancelAfter`. A partial v4 fill credits unused input to the residual owner's pull claim.

`Settled` and `Cancelled` are terminal. However, `settleBatch` does not compare the current time with `cancelAfter`. A callback can still settle a stale `Ready` batch until `cancelStaleBatch` executes; transaction ordering decides a race after `cancelAfter`.

## Guarantees And Limits

The code binds every revealed order field and salt, uses one captured price for matched flow, authorizes only the computed residual request, authenticates settlement, and prevents replay through phase and nonce checks.

It does not provide privacy, censorship resistance, a production oracle, an on-chain price-selection process, or MEV-free residual execution. `MockReferencePrice` is owner-controlled until the snapshot. The residual is public and pool-dependent.

The router authorizes the full computed residual but settles the PoolManager's actual input delta. If v4 reaches `sqrtPriceLimitX96` after consuming less than requested, it returns actual input used and `CommitBatch` credits the unused input token to that residual owner's pull claim. The canonical demo still uses sufficient liquidity so the primary trace is simple, but partial consumption does not strand escrow.
