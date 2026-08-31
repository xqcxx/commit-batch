# CommitBatch Testnet Video Script

This guide records a live CommitBatch lifecycle on Unichain Sepolia. It uses the deployed testnet contracts and three pre-funded, disposable test wallets. It does not deploy contracts, configure Reactive, or require Make.

## What The Presenter Receives

The project owner provides a private handoff bundle containing:

- this repository, including its Git submodules;
- a pre-filled, untracked `demo-operator.env` file;
- confirmation that the operator, Alice, and Bob wallets have Unichain Sepolia ETH; and
- the deployed testnet addresses already present in `demo-operator.env`.

Do not put `demo-operator.env` in a public repository or share it beyond the recording team. The supplied keys and tokens are testnet-only.

The presenter does not need a deployer key, Reactive key, Etherscan API key, funding workflow, or Make.

## Before The Recording

### 1. Open A Terminal

Run all commands from the repository root and keep this terminal open for the entire recording. `DEMO_BATCH_ID` is retained only in this terminal session.

```bash
cd /path/to/commit-batch
```

### 2. Install Required Tools

The terminal needs Foundry and Node.js 20 or newer. Check them first:

```bash
forge --version
node --version
npm --version
```

If Foundry is not installed, install it, open a new terminal, then run `foundryup`:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

If `forge` is not found after installation, open a new terminal or add `~/.foundry/bin` to your shell `PATH`.

```bash
export PATH="$HOME/.foundry/bin:$PATH"
```

### 3. Install Project Dependencies

```bash
git submodule update --init --recursive
npm --prefix frontend ci
```

### 4. Load The Private Demo Configuration

Confirm that the owner-provided `demo-operator.env` is in the repository root. It must contain these values:

```bash
UNICHAIN_SEPOLIA_RPC_URL=https://sepolia.unichain.org
COMMIT_BATCH=0x7401886c04AE20a663a148F42E63378616DE70D4
DEMO_WETH=0x35809A884ddBbEFcc8A97C1565854b81E6bD11Ec
DEMO_USDC=0xd4446d09F2Ee3B836f12481760C1aeB87709a4f4
OPERATOR_PRIVATE_KEY=0x...
ALICE_PRIVATE_KEY=0x...
BOB_PRIVATE_KEY=0x...
ALICE_SALT=0x...
BOB_SALT=0x...
DEMO_BATCH_ID=
DEMO_COMMIT_DURATION=180
DEMO_REVEAL_DURATION=180
```

Load it in Bash:

```bash
set -a
source demo-operator.env
set +a
```

Do not source a deployment `.env` file that contains copied commands or prose.

### 5. Verify The Wallets Have Gas

Derive the three wallet addresses from the supplied keys:

```bash
export OPERATOR_ADDRESS=$(cast wallet address --private-key "$OPERATOR_PRIVATE_KEY")
export ALICE_ADDRESS=$(cast wallet address --private-key "$ALICE_PRIVATE_KEY")
export BOB_ADDRESS=$(cast wallet address --private-key "$BOB_PRIVATE_KEY")
```

Check the balances:

```bash
cast balance "$OPERATOR_ADDRESS" --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL"
cast balance "$ALICE_ADDRESS" --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL"
cast balance "$BOB_ADDRESS" --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL"
```

Each wallet should have at least `0.01 ETH` on Unichain Sepolia. If a balance is lower, stop and ask the project owner to fund it. Do not use a mainnet wallet.

### 6. Prepare A Fresh Recording Batch

Every rehearsal and recording must use fresh salts and a new batch ID. Generate new salts in the current terminal:

```bash
export ALICE_SALT=$(cast keccak "video-alice-$(date +%s%N)")
export BOB_SALT=$(cast keccak "video-bob-$(date +%s%N)")
unset DEMO_BATCH_ID
```

The default commit and reveal windows are three minutes each. Keep `DEMO_COMMIT_DURATION=180` and `DEMO_REVEAL_DURATION=180` for the recording.

### 7. Start The Frontend

In a second terminal, from the repository root, run:

```bash
npm --prefix frontend run dev -- --host 0.0.0.0
```

Open `http://localhost:5173/` in the browser. The frontend is a presentation and deployment-evidence page. The terminal transactions are the live execution evidence.

## Recording

### Opening: Show The Frontend

Action: Open the frontend's Testnet deployment section.

Say:

> This is CommitBatch, deployed on Unichain Sepolia. It is a testnet demonstration of sealed order commitments, uniform batch clearing, internal netting, and Reactive-coordinated settlement.

> The frontend shows the deployed architecture. The terminal actions that follow execute a live testnet batch.

### Stage 1: Create The Batch And Commit Orders

Action: Return to the terminal where `demo-operator.env` was loaded. Run:

```bash
DEMO_STAGE=setup forge script \
  script/RunDemo.s.sol:RunDemo \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" \
  --broadcast --slow -vvvv
```

Action: Read the newly created batch ID and retain it for later stages:

```bash
export DEMO_BATCH_ID=$(cast call "$COMMIT_BATCH" \
  "nextBatchId()(uint64)" \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL")

echo "Live batch: $DEMO_BATCH_ID"
```

Say:

> I have opened a new batch. Alice deposits ten test WETH, and Bob deposits fourteen thousand test USDC.

> Their full order terms are bound into commitment hashes with separate salts. This proves that neither party can change the order after seeing the price captured at commit close.

Action: Point to the two `OrderCommitted` events in the Forge output.

Wait three minutes from the `BatchCreated` transaction before continuing.

### Stage 2: Close Commit And Reveal

Action: Run:

```bash
DEMO_STAGE=reveal forge script \
  script/RunDemo.s.sol:RunDemo \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" \
  --broadcast --slow -vvvv
```

Say:

> The commit window is closed. The contract captures a reference price of two thousand USDC per WETH.

> Alice reveals a ten-WETH sell order, and Bob reveals a fourteen-thousand-USDC buy order. Their salts prove that the reveals match the earlier commitments.

> The orders are both eligible. Seven WETH can match internally against fourteen thousand USDC, leaving a three-WETH residual on Alice's side.

Action: Point to `CommitClosed` and both `OrderRevealed` events.

Wait three minutes from the commit-close transaction before continuing.

### Stage 3: Request Reactive Settlement

Action: Run:

```bash
DEMO_STAGE=request-settlement forge script \
  script/RunDemo.s.sol:RunDemo \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" \
  --broadcast --slow -vvvv
```

Say:

> Reveal is now closed. The settlement contract emits `SettlementRequested`.

> Reactive observes that event and submits the authenticated callback. An externally owned account does not invoke settlement directly.

Action: Point to `SettlementRequested` in the Forge trace. Open the transaction hash printed by Forge in Uniscan and select its Logs tab if explorer evidence is desired.

Wait for the callback. It often completes within minutes. Do not call `settleBatch` manually. Check the batch state:

```bash
cast call "$COMMIT_BATCH" \
  "batches(uint64)(uint64,uint64,uint64,uint64,uint8,uint8,uint8,uint256,uint128,uint128,bool,uint128,uint128)" \
  "$DEMO_BATCH_ID" \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL"
```

The seventh output is the phase: `0=None`, `1=Commit`, `2=Reveal`, `3=Ready`, `4=Settled`, `5=Cancelled`.

Only proceed when the phase is `4`.

Say after phase `4` is returned:

> The authenticated callback has settled the batch. The output reports the internal match and the exact residual swap result.

> Seven WETH crossed internally against fourteen thousand USDC. Only the three-WETH residual used the constrained Uniswap v4 path.

### Stage 4: Claim Outputs

Action: Run:

```bash
DEMO_STAGE=claim forge script \
  script/RunDemo.s.sol:RunDemo \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" \
  --broadcast --slow -vvvv
```

Say:

> Settlement is pull-based. Bob claims the seven WETH that matched internally.

> Alice claims fourteen thousand USDC from the internal match plus the exact output of the residual v4 swap.

> The result is that compatible flow did not traverse the pool. The pool executed only the unmatched residual.

Action: Point to both `OrderClaimed` events. State the exact amounts shown in the live output instead of promising a fixed residual output.

### Closing

Say:

> This is a testnet mechanism demonstration using permissionlessly mintable mock tokens. It demonstrates the commitment, reveal, internal netting, Reactive callback, constrained v4 residual, and pull-based claim lifecycle.

> It does not claim production oracle guarantees, deterministic residual execution, complete MEV elimination, or production-ready token economics.

## Recovery And Rehearsals

- A stage run before its deadline reverts with `InvalidPhase`. Wait longer and rerun only that stage.
- If the callback has not yet arrived, wait and keep checking for phase `4`. Do not call `settleBatch` from an EOA.
- A completed batch cannot be replayed. For another rehearsal, generate new salts, unset `DEMO_BATCH_ID`, and begin again at Stage 1. The next batch ID increments automatically.
- If the phase is `5=Cancelled`, stop that run and start a fresh batch with fresh salts.
- The residual output changes with pool state. Always narrate the value shown by the live `BatchSettled` result.
