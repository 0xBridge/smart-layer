// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAttestationCenter {
    enum PaymentStatus {
        REDEEMED,
        COMMITTED,
        CHALLENGED
    }

    struct PaymentDetails {
        address operator;
        uint256 lastPaidTaskNumber;
        uint256 feeToClaim;
        PaymentStatus paymentStatus;
    }

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

    function numOfActiveOperators() external view returns (uint256);

    function unpause(bytes4 _pausableFlow) external;

    // Only AVS Governance Multisig address can call this function - Disburses funds to the respective operators
    function requestPayment(uint256 _operatorId) external;

    function requestBatchPayment() external;

    function requestBatchPayment(uint256 _from, uint256 _to) external;

    function getOperatorPaymentDetail(uint256 _operatorId) external view returns (PaymentDetails memory);
}
