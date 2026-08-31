# Live Testnet Evidence

## Scope

This page records the deployed CommitBatch demonstration environment. It is a testnet deployment, uses permissionlessly mintable mock tokens, and is not a production deployment or audit attestation.

- Unichain Sepolia chain ID: `1301`
- Reactive Lasna chain ID: `5318007`
- Unichain explorer: `https://sepolia.uniscan.xyz`
- Reactive explorer: `https://lasna.reactscan.net`

## Unichain Sepolia

| Component | Address |
| --- | --- |
| Mock WETH | [`0x35809A884ddBbEFcc8A97C1565854b81E6bD11Ec`](https://sepolia.uniscan.xyz/address/0x35809A884ddBbEFcc8A97C1565854b81E6bD11Ec) |
| Mock USDC | [`0xd4446d09F2Ee3B836f12481760C1aeB87709a4f4`](https://sepolia.uniscan.xyz/address/0xd4446d09F2Ee3B836f12481760C1aeB87709a4f4) |
| Mock reference price | [`0x06B7126A6d206F06D1b52A35C2f0B1068F9Db17D`](https://sepolia.uniscan.xyz/address/0x06B7126A6d206F06D1b52A35C2f0B1068F9Db17D) |
| CommitBatch | [`0x7401886c04AE20a663a148F42E63378616DE70D4`](https://sepolia.uniscan.xyz/address/0x7401886c04AE20a663a148F42E63378616DE70D4) |
| CommitBatchRouter | [`0x3970DA96BDb86Fca28A707D312CE2e15973Af0CF`](https://sepolia.uniscan.xyz/address/0x3970DA96BDb86Fca28A707D312CE2e15973Af0CF) |
| CommitBatchHookFactory | [`0x4a6F46E385b7a8368cAA014857ff81AD841F4dFB`](https://sepolia.uniscan.xyz/address/0x4a6F46E385b7a8368cAA014857ff81AD841F4dFB) |
| CommitBatchHook | [`0x422666fFEBf3E8258998f48fd494bE80a7ba8080`](https://sepolia.uniscan.xyz/address/0x422666fFEBf3E8258998f48fd494bE80a7ba8080) |
| Liquidity seeder | [`0x0b0A701B0f3CB68C75e4E0D48f610C774028fB9E`](https://sepolia.uniscan.xyz/address/0x0b0A701B0f3CB68C75e4E0D48f610C774028fB9E) |
| Uniswap v4 PoolManager | [`0x9cB26A7183B2F4515945Dc52CB4195B0d2D06C95`](https://sepolia.uniscan.xyz/address/0x9cB26A7183B2F4515945Dc52CB4195B0d2D06C95) |

The configured pool has fee `3000`, tick spacing `60`, and pool ID `0x5156d5ea7fd1cccfcdd68aea29aa0987f5c436af309725a06c41910e8860222c`.

## Reactive Lasna

| Component | Address |
| --- | --- |
| CommitBatchRSC | [`0x81E2b89a3aBC0E54FF98425149b864Cf1a21f788`](https://lasna.reactscan.net/address/0x81E2b89a3aBC0E54FF98425149b864Cf1a21f788) |
| Expected ReactVM ID | `0x599282387bcec523E9D10711eE8B396D7644ce13` |

The expected ReactVM ID is the RSC deployer/ReactVM identity, not the RSC contract address.

## Configuration Evidence

- CommitBatch deployment: [`0xeebaab614a35030b69c9a7890993ff874d852577f4ffb85a0b2cdbe549ee1dd6`](https://sepolia.uniscan.xyz/tx/0xeebaab614a35030b69c9a7890993ff874d852577f4ffb85a0b2cdbe549ee1dd6)
- Hook deployment through the factory: [`0xfe113cfa99eb972eef8494615f96924919e2b4ff388863b4ff966ecc67636035`](https://sepolia.uniscan.xyz/tx/0xfe113cfa99eb972eef8494615f96924919e2b4ff388863b4ff966ecc67636035)
- One-time integration configuration: [`0xbb3efebdeb52596d4c176814c6c9a000c78f11fa3ee20897fc973ce0ff19bd2f`](https://sepolia.uniscan.xyz/tx/0xbb3efebdeb52596d4c176814c6c9a000c78f11fa3ee20897fc973ce0ff19bd2f)
- RSC deployment: [`0xd514414400e142f698b9895347bb0b7bd52632758cf2d8fa4f85837b811ea1f9`](https://lasna.reactscan.net/tx/0xd514414400e142f698b9895347bb0b7bd52632758cf2d8fa4f85837b811ea1f9)

Recorded post-deployment checks confirm:

- `CommitBatchRouter.poolConfigured()` is `true`.
- `MockReferencePrice.priceX18()` is `2000000000000000000000`.
- `CommitBatch` stores the published router, hook, and expected ReactVM ID.
- The callback proxy reported zero debt for `CommitBatch` after funding.
- The RSC was Sourcify-verified. Unichain source verification succeeded for the deployed contracts except `CommitBatchHookFactory`, whose explorer submission reported a bytecode mismatch. The factory deployment and hook deployment transactions succeeded; the unverified factory remains a known verification gap.

## Completed Live Batch

Batch `1` completed the canonical lifecycle with distinct disposable operator, Alice, and Bob wallets:

| Step | Transaction |
| --- | --- |
| Create batch and commitments | [`0x8494619fcf198d9d94c493b6bf772aa084f3189bd270ec8ce41232e56c129e9e`](https://sepolia.uniscan.xyz/tx/0x8494619fcf198d9d94c493b6bf772aa084f3189bd270ec8ce41232e56c129e9e) and subsequent commitment transactions |
| Close commit | [`0xf23ab3904b81aff76b7ed65c9e1eec4912f83cb0d0671b840f8cfba2615799cb`](https://sepolia.uniscan.xyz/tx/0xf23ab3904b81aff76b7ed65c9e1eec4912f83cb0d0671b840f8cfba2615799cb) |
| Settlement requested | [`0x40d952b6e88d1c0e421f92654dd3c0ef85451c5627eeb2754e9c7ab945de7ccd`](https://sepolia.uniscan.xyz/tx/0x40d952b6e88d1c0e421f92654dd3c0ef85451c5627eeb2754e9c7ab945de7ccd) |
| Reactive callback and BatchSettled | [`0x1a0b6e65caf76256aae1d0fdd535454718d4c424c47695314d248d40858044b4`](https://sepolia.uniscan.xyz/tx/0x1a0b6e65caf76256aae1d0fdd535454718d4c424c47695314d248d40858044b4) |
| Alice claim | [`0xf2390abfa92b4d931dbc11fcba92f1502c91a1f137259854df54b2781a9c0f0c`](https://sepolia.uniscan.xyz/tx/0xf2390abfa92b4d931dbc11fcba92f1502c91a1f137259854df54b2781a9c0f0c) |
| Bob claim | [`0xed5334381c968a4ea5d68bc91c9ce7b20a4e0c5158f3c2c2d5c491bf320bf49d`](https://sepolia.uniscan.xyz/tx/0xed5334381c968a4ea5d68bc91c9ce7b20a4e0c5158f3c2c2d5c491bf320bf49d) |

The settled batch recorded `7 WETH` matched against `14,000 USDC`, a `3 WETH` base-to-quote residual, and `5,981.999999 USDC` residual output. Alice claimed `19,981.999999 USDC`; Bob claimed `7 WETH`.

## Operating The Demo

Use [`../script.md`](../script.md) for the partner setup and recording procedure. Create a new batch and fresh salts for every rehearsal or recording. Do not redeploy or rerun one-time integration configuration for routine operation.
