// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IReactive } from "reactive-lib/interfaces/IReactive.sol";
import { AbstractReactive } from "reactive-lib/abstract-base/AbstractReactive.sol";

/// @notice Reactive coordinator that turns a closed batch event into an authenticated settlement callback.
contract CommitBatchRSC is AbstractReactive {
    bytes32 public constant SETTLEMENT_REQUESTED = keccak256("SettlementRequested(uint64,uint64)");

    uint256 public immutable originChainId;
    uint256 public immutable destinationChainId;
    address public immutable originSettlement;
    address public immutable destinationSettlement;
    uint64 public immutable callbackGasLimit;
    uint160 public immutable sqrtPriceLimitX96;

    mapping(bytes32 eventId => bool) public processedLog;

    event SettlementCallbackRequested(uint64 indexed batchId, uint64 indexed callbackNonce, bytes32 indexed eventId);

    constructor(
        uint256 originChainId_,
        uint256 destinationChainId_,
        address originSettlement_,
        address destinationSettlement_,
        uint64 callbackGasLimit_,
        uint160 sqrtPriceLimitX96_
    ) payable {
        require(originSettlement_ != address(0) && destinationSettlement_ != address(0), "invalid settlement");
        originChainId = originChainId_;
        destinationChainId = destinationChainId_;
        originSettlement = originSettlement_;
        destinationSettlement = destinationSettlement_;
        callbackGasLimit = callbackGasLimit_;
        sqrtPriceLimitX96 = sqrtPriceLimitX96_;

        if (!vm) {
            service.subscribe(
                originChainId_,
                originSettlement_,
                uint256(SETTLEMENT_REQUESTED),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function react(IReactive.LogRecord calldata log) external override vmOnly {
        if (
            log.chain_id != originChainId || log._contract != originSettlement
                || log.topic_0 != uint256(SETTLEMENT_REQUESTED)
        ) return;

        bytes32 eventId = keccak256(abi.encode(log.chain_id, log.tx_hash, log.log_index));
        if (processedLog[eventId]) return;
        processedLog[eventId] = true;

        uint64 batchId = uint64(log.topic_1);
        uint64 callbackNonce = uint64(log.topic_2);
        bytes memory payload = abi.encodeWithSignature(
            "settleBatch(address,uint64,uint64,uint160)", address(this), batchId, callbackNonce, sqrtPriceLimitX96
        );
        emit Callback(destinationChainId, destinationSettlement, callbackGasLimit, payload);
        emit SettlementCallbackRequested(batchId, callbackNonce, eventId);
    }
}
