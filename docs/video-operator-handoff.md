# Video Operator Handoff

## Scope

This is a testnet recording procedure. The operator uses only three disposable demo-wallet keys: an operator, Alice, and Bob. Never give the deployer key, Reactive key, or `.env` containing them to the video presenter.

## Pre-Recording Setup

The project owner performs these tasks before handing over the demo:

- verify all Unichain contracts and the Lasna RSC;
- fund the RSC and destination callback account;
- run the one-time integration configuration;
- create operator, Alice, and Bob wallets; fund each with a small amount of Unichain Sepolia ETH; and put their private keys and salts only in a restricted `demo-operator.env` file;
- set `COMMIT_BATCH`, `DEMO_WETH`, `DEMO_USDC`, and the three demo keys/salts in that file.

The deployed `MockERC20` tokens are permissionlessly mintable and must never be represented as production tokens.

## Operator Commands

For Fish, create the restricted `demo-operator.fish` file from `demo-operator.fish.example`, populate its three disposable wallet keys and two salts, then load it from the repository root:

```bash
source demo-operator.fish
```

### Stage 1: Create And Commit

Set a fresh batch ID to the current `nextBatchId + 1`, then run:

```bash
export DEMO_STAGE=setup
forge script script/RunDemo.s.sol:RunDemo --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" --broadcast --slow -vvvv
```

The operator records the emitted `BatchCreated` event and writes its batch ID to `DEMO_BATCH_ID` in `demo-operator.env`. It can also read the new ID directly:

```bash
cast call "$COMMIT_BATCH" "nextBatchId()(uint64)" --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL"
```

This stage mints `10 WETH` to Alice and `14,000 USDC` to Bob, creates a three-minute commit and reveal window, approves escrow, and submits both binding commitments.

### Stage 2: Close Commit And Reveal

Wait until the `commitDeadline` from `getBatch(DEMO_BATCH_ID)` has passed. Then:

```bash
export DEMO_STAGE=reveal
forge script script/RunDemo.s.sol:RunDemo --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" --broadcast --slow -vvvv
```

### Stage 3: Request Reactive Settlement

Wait until `revealDeadline` has passed. Then:

```bash
export DEMO_STAGE=request-settlement
forge script script/RunDemo.s.sol:RunDemo --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" --broadcast --slow -vvvv
```

Show `SettlementRequested`, then wait for the Reactive callback to produce `BatchSettled`. Do not call `settleBatch` from an EOA.

### Stage 4: Claim

After `BatchSettled`:

```bash
export DEMO_STAGE=claim
forge script script/RunDemo.s.sol:RunDemo --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" --broadcast --slow -vvvv
```

When inspecting `batches(batchId)`, phase values are `0=None`, `1=Commit`, `2=Reveal`, `3=Ready`, `4=Settled`, and `5=Cancelled`.

## Spoken Narrative

1. "Alice commits 10 WETH and Bob commits 14,000 USDC. The commitments bind the full order and a secret salt."
2. "After the commit window, the reference price is captured at 2,000 USDC per WETH, then both orders reveal."
3. "Seven WETH matches internally against 14,000 USDC. Only Alice's three-WETH residual goes to Uniswap v4 through the constrained hook."
4. "Reactive observes the settlement request and the authenticated callback settles the batch."
5. "Bob claims seven WETH. Alice claims 14,000 USDC plus the actual residual swap output."

Do not claim privacy, a production oracle, deterministic residual output, or complete MEV elimination.
