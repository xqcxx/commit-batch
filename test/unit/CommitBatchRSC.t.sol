// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "reactive-lib/interfaces/IReactive.sol";
import { CommitBatchRSC } from "../../src/reactive/CommitBatchRSC.sol";

contract CommitBatchRSCTest is Test {
    uint256 private constant CHAIN_ID = 1301;
    address private constant SETTLEMENT = address(0xBA7C);
    CommitBatchRSC private rsc;

    function setUp() public {
        rsc = new CommitBatchRSC(CHAIN_ID, CHAIN_ID, SETTLEMENT, SETTLEMENT, 700_000, 4_295_128_740);
    }

    function test_RelevantLogIsProcessedExactlyOnce() public {
        IReactive.LogRecord memory log = _log();
        rsc.react(log);
        bytes32 eventId = keccak256(abi.encode(CHAIN_ID, log.tx_hash, log.log_index));
        assertTrue(rsc.processedLog(eventId));
        rsc.react(log);
        assertTrue(rsc.processedLog(eventId));
    }

    function test_UnrelatedLogIsIgnored() public {
        IReactive.LogRecord memory log = _log();
        log._contract = address(0xBAD);
        rsc.react(log);
        bytes32 eventId = keccak256(abi.encode(CHAIN_ID, log.tx_hash, log.log_index));
        assertFalse(rsc.processedLog(eventId));
    }

    function _log() private view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chain_id: CHAIN_ID,
            _contract: SETTLEMENT,
            topic_0: uint256(rsc.SETTLEMENT_REQUESTED()),
            topic_1: 7,
            topic_2: 9,
            topic_3: 0,
            data: "",
            block_number: block.number,
            op_code: 0,
            block_hash: 1,
            tx_hash: 2,
            log_index: 3
        });
    }
}
