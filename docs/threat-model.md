# CommitBatch Threat Model

## Security Objectives

1. A reveal opens only the exact order and salt bound by its depositor's commitment.
2. A batch settles only when both opposite orders are revealed and eligible.
3. Matched flow exchanges at the captured `clearingPriceX18` without per-order priority.
4. Only the Callback Proxy presenting the expected RVM ID and callback nonce can settle.
5. The hook consumes one authorization for the computed residual request.
6. Claims and refunds are pull-based and cannot be repeated.

## Trust Boundaries

The demo trusts the owner of `MockReferencePrice`, the configured Callback Proxy and RVM identity, Reactive infrastructure, Uniswap v4 PoolManager, the one-time router/hook configuration, pool liquidity, and standard ERC-20 behavior. `MockReferencePrice` is deliberately not a production oracle. Its owner can change `priceX18` until `closeCommit` captures it.

Traders, ordinary callers, public observers, and direct router callers are untrusted. Commitments do not hide direction or size: `commit` calldata, transfers, and `getCommitment` expose them.

## Threats And Controls

| Threat | Implemented control | Remaining limitation |
| --- | --- | --- |
| Reveal mutation | `keccak256(abi.encode(order, salt))`; owner, direction, amount, recipient, deposit, and nonce checks | Weak salts permit guessing; no privacy claim |
| Reveal copied | Depositor, `order.owner`, and `msg.sender` must match | Public reveal remains observable |
| Replay | Per-owner nonce consumed on valid reveal; batch ID hash-bound | Nonces are global per owner and never reusable |
| Same-side or same-owner pair | Rejected when the second commitment is submitted | Direction and deposit are disclosed at commit |
| Early/late phase action | Commit/reveal and close functions enforce their deadlines and phases | Inclusion near timestamp boundaries can vary |
| Price changed after close | Stored `clearingPriceX18` is used at reveal and settlement | Mock owner controls the value before close |
| Unacceptable output | Reference eligibility and final per-order `minAmountOut`; v4 `sqrtPriceLimitX96` | No per-order limit price; residual may revert or face MEV |
| Forged settlement | `msg.sender == callbackProxy`, supplied RVM ID, `Ready` phase, and callback nonce | Trusted proxy/RVM compromise or bad configuration |
| Forged RSC log | RSC filters chain, emitter, and event topic; deduplicates log identity | Tests cover relevant/unrelated log and dedup state, not live infrastructure |
| Residual over-request/reuse | Exact amount and parameters hash-bound in one active authorization; hook consumes it | One global authorization slot; external call must remain atomic |
| Wrong pool direction | Router maps protocol direction to currency order; hook independently verifies it | Integration mistakes or PoolManager defects remain |
| Residual sandwich/backrun | Only net input reaches v4; exact request, price limit, and final minimum constrain execution | Residual MEV is not eliminated |
| Reentrancy | `commit`, `settleBatch`, `claim`, and `refund` are guarded; claim/refund state changes precede transfer | Nonstandard callback-enabled tokens are unsupported |
| Claim theft | Only commitment owner may call; transfer goes to hash-bound recipient | Recipient key compromise is out of scope |
| Missing reveal/ineligibility | Whole batch cancels at `closeReveal`; full owner refunds | No partial or one-sided settlement |
| Missing callback | Anyone can call `cancelStaleBatch` at `cancelAfter` | Funds remain locked until someone cancels and users refund |
| Timeout race | Settlement and cancellation each require `Ready`; first successful transaction changes phase | `settleBatch` has no time check, so stale settlement remains possible before cancellation |
| Arithmetic overflow | Solidity checked arithmetic reverts | No full-precision `mulDiv`; large valid economic values may revert |
| Partial v4 input use | Router returns actual input used and output; unused input becomes a pull credit | Real price-limit partial fill is not yet an integration test |

## Cancellation Semantics

Each batch stores:

```text
cancelAfter = revealDeadline + cancellationDelay
```

If a batch is still `Ready` at or after `cancelAfter`, anyone may call `cancelStaleBatch`. It changes phase to `Cancelled`, after which each owner can call `refund` for the full deposit.

This is not a hard settlement deadline. `settleBatch` checks phase and callback nonce but not `block.timestamp` or `cancelAfter`. Therefore an authenticated callback can settle after `cancelAfter` while phase remains `Ready`. If cancellation executes first, the callback fails because phase is `Cancelled`. Documentation and demos must not claim that a late callback automatically reverts before cancellation.

## Residual Accounting

The authorization and `Batch.residualIn` describe requested exact input. v4 can stop at `sqrtPriceLimitX96` with a smaller actual negative input delta. The router returns actual input used and actual output. If input used is smaller than the authorization, `CommitBatch` records the difference as an additional claimable input-token credit for the residual owner. `claim` transfers both normal output and this unused-input credit to the committed recipient.

The canonical demo should still configure sufficient liquidity and a price limit expected to consume all `3 WETH`, so its main visual remains one clean residual execution. This is a presentation choice, not a stranded-funds limitation.

## Explicit Non-Claims

- No transaction, sender, direction, amount, or escrow privacy.
- No censorship resistance or guaranteed inclusion.
- No production-safe or manipulation-resistant reference price.
- No order-level limit price.
- No optimal execution guarantee and no removal of residual MEV.
- No hard settlement cutoff at `cancelAfter`.
- No support claim for fee-on-transfer, rebasing, callback-enabled, or otherwise nonstandard tokens.
- No comprehensive proof of conservation, overflow safety, or all decimal combinations from the current tests.

## Verified Tests

The repository currently tests canonical and quote-side clearing, a bounded fuzz invariant, invalid salts, callback sender/RVM authentication and replay, missing-reveal cancellation/refunds, opposite owner/direction restrictions, stale cancellation timing, RSC log filtering/deduplication, partial residual unused-input credits through the mock executor, and one real PoolManager/hook residual path.

It does not currently test post-`cancelAfter` settlement before cancellation, partial residual consumption at a real v4 price limit, unauthorized claims, reentrancy, broad arithmetic boundaries, or all negative hook/router cases. These remain review and test gaps rather than demo-proven properties.
