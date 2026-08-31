import assert from 'node:assert/strict'
import test from 'node:test'
import { encodeAbiParameters, keccak256, stringToBytes } from 'viem'

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
}

function commitment(order, salt) {
  return keccak256(encodeAbiParameters([orderParameter, { type: 'bytes32' }], [order, salt]))
}

test('TypeScript canonical hash matches the Solidity abi.encode fixture', () => {
  const alice = '0x00000000000000000000000000000000000A11cE'
  const order = { batchId: 1n, owner: alice, zeroForOne: true, amountIn: 10n * 10n ** 18n, minAmountOut: 19_900n * 10n ** 6n, recipient: alice, nonce: 1n }
  const salt = keccak256(stringToBytes('alice-demo-salt'))
  assert.equal(commitment(order, salt), '0x11b90d23547d4002e1c2d0bb9a9de8dca1113210838e680f7c36c453ab8c9577')
  assert.notEqual(commitment({ ...order, amountIn: 9n * 10n ** 18n }, salt), commitment(order, salt))
})

test('fixed scenario nets seven WETH and leaves three WETH residual', () => {
  const aliceWeth = 10n * 10n ** 18n
  const bobUsdc = 14_000n * 10n ** 6n
  const priceX18 = 2_000n * 10n ** 18n
  const matchedWeth = (bobUsdc * 10n ** 12n * 10n ** 18n) / priceX18
  assert.equal(matchedWeth, 7n * 10n ** 18n)
  assert.equal(aliceWeth - matchedWeth, 3n * 10n ** 18n)
})
