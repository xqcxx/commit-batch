# CommitBatch

CommitBatch binds two opposite exact-input orders, crosses compatible flow at one captured price, and sends only the net imbalance through an authorized Uniswap v4 swap triggered by Reactive Network.

## Canonical Result

At the fixed `2,000 USDC/WETH` demo price:

| Order | Internal match | v4 residual |
| --- | ---: | ---: |
| Alice sells `10 WETH` | `7 WETH` for `14,000 USDC` | `3 WETH` |
| Bob sells `14,000 USDC` | `14,000 USDC` for `7 WETH` | none |

The batch makes one AMM call with `3 WETH`. Measured in WETH at the reference price, this is an `82.35%` reduction in AMM-routed input versus routing both gross sides (`17 WETH` equivalent). This number is a flow-reduction result, not a gas, price-impact, execution-quality, or MEV-savings guarantee. Alice receives `14,000 USDC` plus the actual v4 output for the residual; Bob receives `7 WETH`.

## Architecture

```text
traders -> CommitBatch escrow -> commit close / price snapshot -> reveals
                                                              |
                                        SettlementRequested event
                                                              v
                                                  CommitBatchRSC
                                                              |
                                             authenticated callback
                                                              v
UniformClearing <- CommitBatch settlement -> CommitBatchRouter -> v4 PoolManager
                                                  |
                                          CommitBatchHook validates
                                          the one-time authorization
```

- `CommitBatch` owns escrow, phases, the two commitment slots, the reference-price snapshot, settlement accounting, claims, refunds, and one-time residual authorization.
- `UniformClearing` calculates the matched base/quote amounts and the single residual using integer floor rounding.
- `CommitBatchRouter` executes the exact-input residual against its configured v4 pool and returns actual pool output to settlement.
- `CommitBatchHook` permits only the configured router and consumes an authorization bound to batch, nonce, direction, input amount, and `sqrtPriceLimitX96`.
- `CommitBatchRSC` filters `SettlementRequested` logs and asks Reactive Network to call settlement. The destination still authenticates the Callback Proxy, RVM identity, batch phase, and callback nonce.
- The React frontend is a deterministic fixture viewer. It has no wallet connection or live transaction path.

Each batch accepts at most two owners and requires opposite directions. Both orders must be present, revealed, and eligible or the batch is cancelled. Matched flow uses the captured mock `X18` reference price; the residual uses current v4 pool execution. Outputs are claimed in separate transactions.

## v4 And Reactive

Uniswap v4 is deliberately the residual path, not the matching engine. Opposing inventory crosses inside `CommitBatch`; only the computed imbalance reaches the fixed router/pool, where the hook verifies and atomically consumes a single-use authorization before the swap.

Reactive Network is the cross-chain automation path, not a solver or price source. The RSC cannot choose allocation or reference price: it converts a valid origin event into a callback carrying the batch ID, callback nonce, RVM identity, and configured v4 price limit. If settlement remains `Ready` at `cancelAfter`, anyone may cancel and unlock full refunds. As currently implemented, time alone does not invalidate settlement: an authenticated callback can still win after `cancelAfter` if cancellation has not yet executed; whichever valid transaction changes the phase first wins.

## Privacy And MEV Limits

The commitment is **binding, not private**. Its hash binds batch ID, owner, direction, amount, minimum output, recipient, nonce, and salt, but `commit` calldata separately publishes direction and deposit amount. The sender, token approval, escrow transfer, timing, contract storage, and later reveal are public. A weak salt may permit preimage guessing. CommitBatch does not hide identities, balances, order size, direction, or transaction metadata, and it does not prevent censorship or deadline-edge ordering.

Matched flow has no within-batch execution priority and does not touch the AMM. That narrows the exposed swap from gross flow to net flow, but does not make execution MEV-free. The revealed residual and callback are public; searchers can influence pool state, sandwich the residual, or backrun it. Loss is constrained by the exact authorized input, the configured v4 `sqrtPriceLimitX96`, and each committed order's end-to-end `minAmountOut`, but settlement may revert and funds may remain escrowed until settlement or cancellation. The administrator-controlled mock reference source is reproducible demo infrastructure, not a manipulation-resistant production oracle.

## Repository Map

| Path | Purpose |
| --- | --- |
| [`src/core`](./src/core) | Escrow, lifecycle, settlement, and clearing math |
| [`src/reactive`](./src/reactive) | Reactive Smart Contract event-to-callback coordinator |
| [`src/v4`](./src/v4) | Residual v4 router |
| [`src/hook`](./src/hook) | v4 authorization hook |
| [`test`](./test) | Foundry unit and integration tests, including a real local v4 `PoolManager` path |
| [`frontend`](./frontend) | Static React/TypeScript demonstration and commitment fixture |
| [`shared/canonical-scenario.json`](./shared/canonical-scenario.json) | Canonical `10 WETH` / `14,000 USDC` result |
| [`docs`](./docs) | Architecture, clearing, threat model, deployment, and demo material |
| [`deployments`](./deployments) | Live Unichain Sepolia and Reactive Lasna testnet manifests |
| [`slides/deck.md`](./slides/deck.md) | Presentation deck source |

## Install, Test, Build

Prerequisites: [Foundry](https://book.getfoundry.sh/getting-started/installation), Node.js 20+, npm, and Git.

```bash
git submodule update --init --recursive
npm --prefix frontend ci
forge test
forge build
npm --prefix frontend test
npm --prefix frontend run build
```

`Makefile` targets are optional shortcuts. The project does not require Make: use `npm --prefix frontend run dev -- --host 0.0.0.0` to start the frontend.

## Deployment Status

**Live testnet only.** The Unichain Sepolia settlement stack and Reactive Lasna coordinator are deployed and wired. The current addresses and transaction evidence are in [`docs/live-testnet.md`](./docs/live-testnet.md), [`deployments/unichain-sepolia.json`](./deployments/unichain-sepolia.json), and [`deployments/reactive-lasna.json`](./deployments/reactive-lasna.json).

The deployed WETH and USDC contracts are permissionlessly mintable mocks. They are not production assets. `MockReferencePrice` is owner-controlled demo infrastructure, not a production oracle. The one-time integration has already been configured; do not run `ConfigureReactiveIntegration.s.sol` against this deployment again.

## Test Evidence

| Suite | Evidence |
| --- | --- |
| Foundry unit | Canonical and opposite residual math, a bounded conservation fuzz property, and Reactive source filtering/deduplication |
| Foundry integration | Full commit/reveal/settle/claim lifecycle, refund path, callback authentication/replay, timeout cancellation, slot constraints, and residual execution through a local real v4 `PoolManager` plus hook |
| Frontend | Two Node tests cover Solidity-compatible ABI commitment hashing and the canonical `7 WETH` matched / `3 WETH` residual fixture |
| CI | [`.github/workflows/ci.yml`](./.github/workflows/ci.yml) runs `forge test`, `forge build`, frontend tests, and the production frontend build on every push and pull request |

The suite contains 14 Foundry tests and two frontend commitment tests. Run the commands above in a clean checkout to reproduce current results.

## Demo And Docs

- [Partner recording guide](./script.md)
- [Demo runbook](./docs/demo-runbook.md)
- [Four-minute demo script](./docs/demo-script.md)
- [Architecture](./docs/architecture.md)
- [Clearing rule](./docs/clearing-rule.md)
- [Threat model](./docs/threat-model.md)
- [Deployment guide](./docs/deployment-guide.md)
- [Live testnet evidence](./docs/live-testnet.md)
- [Frontend usage](./frontend/README.md)

## License

[MIT](./LICENSE)
