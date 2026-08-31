# CommitBatch frontend

A static React 19 + TypeScript demonstration of commit/reveal intent netting and residual execution authorization.

## Fixed scenario

- Alice sells 10 WETH.
- Bob sells 14,000 USDC at 2,000 USDC/ETH.
- 7 WETH crosses internally for 14,000 USDC.
- Alice's remaining 3 WETH is the only residual authorized for external routing.

All balances, events, hashes, and outcomes in the interface are deterministic demo fixtures. There is no wallet connection or live transaction path. The deployment manifest at `public/deployments/testnet.json` lists the live Unichain Sepolia and Reactive Lasna testnet addresses; it does not make the fixture timeline live or interactive.

## Commands

```bash
npm install
npm run dev
npm test
npm run build
```

## Commitment fixture

The UI and Node test use ABI encoding equivalent to Solidity's `keccak256(abi.encode(order, salt))`:

```text
Order(uint64 batchId, address owner, bool zeroForOne, uint128 amountIn,
      uint128 minAmountOut, address recipient, uint64 nonce), bytes32 salt
```

The fixture demonstrates binding and determinism only. Commitments do not provide anonymity, conceal deposit/timing metadata, or compensate for weak salts.
