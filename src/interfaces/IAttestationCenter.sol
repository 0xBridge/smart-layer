// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAttestationCenter {
    struct TaskInfo {
        string proofOfTask;
        bytes data;
        address taskPerformer;
        uint16 taskDefinitionId;
    }

    function submitTask(
        TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata _tpSignature,
        uint256[2] calldata _taSignature,
        uint256[] calldata _attestersIds
    ) external;

    function unpause(bytes4 _pausableFlow) external;
    // Only AVS Governance Multisig address can call this function - Disburses funds to the respective operators
    function requestBatchPayment() external;
}
