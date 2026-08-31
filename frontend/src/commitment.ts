import { encodeAbiParameters, keccak256, stringToBytes, type Address, type Hex } from 'viem'

export type Order = {
  batchId: bigint
  owner: Address
  zeroForOne: boolean
  amountIn: bigint
  minAmountOut: bigint
  recipient: Address
  nonce: bigint
}

const orderParameter = {
  type: 'tuple',
  components: [
    { name: 'batchId', type: 'uint64' },
    { name: 'owner', type: 'address' },
    { name: 'zeroForOne', type: 'bool' },
    { name: 'amountIn', type: 'uint128' },
    { name: 'minAmountOut', type: 'uint128' },
    { name: 'recipient', type: 'address' },
    { name: 'nonce', type: 'uint64' },
  ],
} as const

export function saltFromLabel(label: string): Hex {
  return keccak256(stringToBytes(label))
}

export function makeCommitment(order: Order, salt: Hex): Hex {
  return keccak256(encodeAbiParameters([orderParameter, { type: 'bytes32' }], [order, salt]))
}
