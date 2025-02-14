// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract TasksRegistry {
    // struct TaskInfo {
    //     string proofOfTask;
    //     bytes data;
    //     address taskPerformer;
    //     uint16 taskDefinitionId;
    // }

    struct TaskInfo {
        bytes32 blockHash;
        bytes32[] proof;
        uint256 index;
        bytes psbtData;
        bytes options;
        address refundAddress;
    }

    mapping(bytes32 btcTxnHash => TaskInfo) private tasks;

    event TaskCreated(
        bytes32 btcTxnHash,
        bytes32 blockHash,
        bytes32[] proof,
        uint256 index,
        bytes psbtData,
        bytes options,
        address refundAddress
    );

    constructor() {}

    function createTask(
        bytes32 _blockHash,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _psbtData,
        bytes calldata _options,
        address _refundAddress
    ) external {
        TaskInfo memory _taskInfo = TaskInfo({
            blockHash: _blockHash,
            proof: _proof,
            index: _index,
            psbtData: _psbtData,
            options: _options,
            refundAddress: _refundAddress
        });
        tasks[_btcTxnHash] = _taskInfo;
        // Emit whatever event you'd want the attesters to listen to
        emit TaskCreated(_btcTxnHash, _blockHash, _proof, _index, _psbtData, _options, _refundAddress);
    }
}
