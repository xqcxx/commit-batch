# Deployment Guide

## Live Testnet And Deployment Scope

- Settlement/origin: Unichain Sepolia (`1301`)
- Reactive coordinator: Reactive Lasna (`5318007`)
- Price source: `MockReferencePrice` for the mechanism demo
- Pair: base token assumed to have 18 decimals; quote token configured with at most 18 decimals

The live testnet addresses and transaction evidence are maintained in [`live-testnet.md`](./live-testnet.md). `script/DeployUnichainDemo.s.sol` is for a fresh deployment of the mock pair, controlled price source, `CommitBatch`, router, CREATE2-mined hook, initialized pool, and demo liquidity. `script/DeployRSC.s.sol` deploys the coordinator after the settlement address is known. `script/ConfigureReactiveIntegration.s.sol` performs irreversible final wiring and must not be rerun against the published deployment.

## Configuration

| Value | Used by code |
| --- | --- |
| PoolManager | `CommitBatchRouter` and `CommitBatchHook` constructors |
| Base/quote token | `CommitBatch`, router, and hook constructors |
| Quote decimals | `CommitBatch`; base is assumed 18 decimals by clearing math |
| Reference price | `IReferencePrice` immutable in `CommitBatch` |
| Callback Proxy | Immutable settlement caller in `CommitBatch` |
| Cancellation delay | Immutable delay added to each reveal deadline |
| Pool key | Stored by `CommitBatchRouter`; must contain the same two tokens and hook |
| Expected RVM ID | Set once by `configureIntegrations` |
| Etherscan API key | Used by `forge script --verify` for Uniscan verification |
| Callback gas and square-root price limit | Fixed in `CommitBatchRSC` |
| RSC deployment value | Native lREACT sent to the payable RSC constructor for subscription setup |

Use official network registries to obtain PoolManager, Callback Proxy, chain IDs, and Reactive infrastructure addresses. Do not infer addresses from this guide.

## Deployment Order

### 1. Set Environment

Create `.env` from `.env.example` and provide a funded deployer key, the current Unichain Sepolia PoolManager/Reactive Callback Proxy addresses from official registries, RPC URLs, and the fixed callback limit. Do not commit `.env`.

```bash
set -a
source .env
set +a
forge test
```

### 2. Deploy Unichain Components

Run:

```bash
forge script script/DeployUnichainDemo.s.sol:DeployUnichainDemo \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" --broadcast \
  --verify --verify-external \
  --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=1301" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  -vvvv
```

The script mines a CREATE2 salt whose hook address has only the `beforeSwap` permission flag, deploys the hook through `CommitBatchHookFactory`, initializes the pool at the demo `2,000 USDC/WETH` price, and seeds full-range mock-token liquidity. `--verify` submits contracts found in deployment receipts after broadcasting; `--verify-external` also opts into verification for the hook deployed through the factory. Copy the emitted addresses into `.env`, deployment manifests, and the frontend manifest. Do not call `configureIntegrations` yet because the Lasna RSC has not been deployed.

Unichain uses Uniscan, whose API has migrated to the Etherscan V2-compatible endpoint. It is not a Sourcify-only deployment. If verification is interrupted after broadcasting, rerun the same command with `--resume --verify` instead of deploying again.

### 3. Tokens And Price Source

Deploy or select demo tokens. For the canonical fixture, WETH is base with 18 decimals and USDC is quote with 6 decimals.

Deploy:

```solidity
new MockReferencePrice(owner, 2_000e18)
```

The owner can call `setPrice`; `closeCommit` later freezes the then-current value per batch. This source is controlled demo infrastructure, not an oracle.

### 4. `CommitBatch`

Deploy:

```solidity
new CommitBatch(
    owner,
    baseToken,
    quoteToken,
    quoteDecimals,
    referencePrice,
    callbackProxy,
    cancellationDelay
)
```

`cancellationDelay` must be nonzero. `quoteDecimals` must be at most 18. The constructor does not inspect token metadata.

### 5. Hook, Router, And Pool

`CommitBatchRouter` deploys before the hook, but cannot execute until its owner calls one-time `configurePool(poolKey)`. `CommitBatchHookFactory` now mines a CREATE2 address whose low permission bits encode `beforeSwap`, using the known router address in hook constructor arguments. Deploy the router, mine/deploy the hook, construct the pool key with exactly those tokens and that hook, then call `router.configurePool(poolKey)`. The full Unichain script follows this order.

Initialize and fund the pool. Choose the RSC `sqrtPriceLimitX96` for the canonical base-to-quote residual and verify it against currency ordering and current pool price. If a price limit partially fills, `CommitBatch` credits unused residual input to that order's pull claim; still use sufficient liquidity for a clear canonical demo trace.

Call the owner-only one-time wiring function:

```solidity
commitBatch.configureIntegrations(router, hook, expectedRvmId);
```

This stores all three addresses permanently and approves the router for unlimited base and quote amounts.

### 6. `CommitBatchRSC` And Final Wiring

Deploy:

```solidity
new CommitBatchRSC(
    originChainId,
    destinationChainId,
    address(commitBatch),
    address(commitBatch),
    callbackGasLimit,
    sqrtPriceLimitX96
)
```

For a same-chain origin/destination settlement, both contract arguments are the same `CommitBatch`. The RSC subscribes to its `SettlementRequested(uint64,uint64)` event. The Reactive system contract creates the associated ReactVM during that constructor call, which Foundry's `forge script` preflight can reject. Deploy directly on Lasna:

```bash
forge create src/reactive/CommitBatchRSC.sol:CommitBatchRSC \
  --rpc-url "$REACTIVE_LASNA_RPC_URL" --chain-id 5318007 \
  --private-key "$PRIVATE_KEY" --broadcast --value "${RSC_DEPLOYMENT_VALUE:-10000000000000000}" \
  --verify --verifier sourcify -vvvv \
  --constructor-args "$ORIGIN_CHAIN_ID" "$DESTINATION_CHAIN_ID" "$COMMIT_BATCH" "$COMMIT_BATCH" \
  "$CALLBACK_GAS_LIMIT" "$SQRT_PRICE_LIMIT_X96"
```

Lasna's public Reactscan documentation does not currently document an Etherscan-compatible source-verification endpoint. The Sourcify command is safe to try and verification is separate from deployment; if it is unsupported, retain the exact compiler settings and constructor arguments and use the explorer's available workflow. Do not rerun deployment just because source verification fails.

Reactive replaces the callback's first address argument with the ReactVM ID, which its documentation defines as the Lasna RSC deployer's address. Set `EXPECTED_RVM_ID` to that Lasna deployer EOA, not the deployed RSC contract address. Then, back on Unichain, perform the irreversible wiring:

```bash
forge script script/ConfigureReactiveIntegration.s.sol:ConfigureReactiveIntegration \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" --broadcast -vvvv
```

Ensure the Reactive payment mechanism is funded and verify the exact origin chain, emitter, and topic subscription.

## Batch Operation

Create a batch with durations, not absolute timestamps:

```solidity
uint64 batchId = commitBatch.createBatch(commitDuration, revealDuration);
```

The contract computes:

```text
commitDeadline = now + commitDuration
revealDeadline = commitDeadline + revealDuration
cancelAfter    = revealDeadline + cancellationDelay
```

`createBatch` is permissionless and does not restrict concurrent batches.

For the canonical fixture, fund Alice with `10 WETH`, Bob with `14,000 USDC`, and both with gas. Each trader approves `CommitBatch`, computes `keccak256(abi.encode(order, salt))`, and calls `commit` with the same direction and amount as the hidden order.

## Verification

Record and verify:

| Component | Required evidence |
| --- | --- |
| `MockReferencePrice` | Address, owner, and `priceX18 == 2_000e18` before close |
| `CommitBatch` | Tokens, quote decimals, source, Callback Proxy, cancellation delay |
| `CommitBatchHook` | PoolManager, settlement, router, tokens, before-swap permission bits |
| `CommitBatchRouter` | PoolManager, settlement, tokens, full pool key |
| Integrations | Stored router, hook, and expected RVM ID |
| `CommitBatchRSC` | Chain IDs, origin/destination settlement, gas limit, square-root price limit |
| Reactive | Exact event subscription and funding |

Before presenting, run `forge test`. The current suite provides local lifecycle, math, RSC, and real PoolManager/hook coverage. It is not a fork deployment test or production audit.

## Operations

Monitor `BatchCreated`, `OrderCommitted`, `CommitClosed`, `OrderRevealed`, `SettlementRequested`, `ResidualAuthorized`, `ResidualAuthorizationConsumed`, `ResidualExecuted`, `BatchSettled`, `OrderClaimed`, `BatchCancelled`, and `OrderRefunded`.

If settlement is delayed, inspect the RSC subscription/funding, callback gas, Callback Proxy, expected RVM ID, batch phase, callback nonce, pool liquidity, and square-root price limit. An EOA cannot bypass callback authentication.

At or after `cancelAfter`, anyone may call `cancelStaleBatch` while phase is `Ready`. Do not describe this as an automatic or hard timeout: an authenticated callback can still settle until cancellation is mined. Once cancellation succeeds, owners pull full refunds and later settlement fails on phase.
