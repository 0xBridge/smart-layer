// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAttestationCenter {
    struct TaskInfo {
        string proofOfTask;
        bytes data;
        address taskPerformer;
        uint16 taskDefinitionId;
    }

    struct EcdsaTaskSubmissionDetails {
        bool isApproved;
        bytes tpSignature;
        uint256[2] taSignature;
        uint256[] attestersIds;
    }

    function submitTask(TaskInfo calldata _taskInfo, EcdsaTaskSubmissionDetails calldata _ecdsaTaskSubmissionDetails)
        external;

    function unpause(bytes4 _pausableFlow) external;
    // Only AVS Governance Multisig address can call this function - Disburses funds to the respective operators
    function requestBatchPayment() external;
}
