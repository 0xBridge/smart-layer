// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// TODO: NOTE the license provided by Othentic

interface IAttestationCenter {
    struct TaskInfo {
        string proofOfTask;
        bytes data;
        address taskPerformer;
        uint16 taskDefinitionId;
    }
}

interface IAvsLogic {
    // function afterTaskSubmission(
    //     IAttestationCenter.TaskInfo calldata _taskInfo,
    //     bool _isApproved,
    //     bytes calldata _tpSignature,
    //     uint256[2] calldata _taSignature,
    //     uint256[] calldata _attestersIds
    // ) external;

    function beforeTaskSubmission(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata _tpSignature,
        uint256[2] calldata _taSignature,
        uint256[] calldata _attestersIds
    ) external;
}
