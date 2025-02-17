// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {BN254} from "@eigenlayer-middleware/src/libraries/BN254.sol";
import {HomeChainCoordinator} from "./HomeChainCoordinator.sol";
import {IAttestationCenter, IAvsLogic} from "./interfaces/IAvsLogic.sol";
import {IOBLS} from "./interfaces/IOBLS.sol";

/**
 * @title OxBridgeAVS
 * @dev Implementation of a secure 0xBridge AVS logic with ownership and pause functionality
 */
contract OxBridgeAVS is Ownable, Pausable, ReentrancyGuard, IAvsLogic {
    using BN254 for BN254.G1Point;

    // Errors
    error TaskNotFound();
    error InvalidTask();
    error TaskAlreadyCompleted();

    // Constants
    uint256 internal constant _THRESHOLD_DENOMINATOR = 100;

    // Task storage
    struct TaskData {
        bytes32 blockHash;
        bytes32 btcTxnHash;
        bytes32[] proof;
        uint256 index;
        bytes psbtData;
        bytes options;
    }

    mapping(uint32 => TaskData) public taskData;
    mapping(uint32 => bool) public completedTasks;

    // mapping of task indices to hash of abi.encode(taskResponse, taskResponseMetadata)
    // mapping(uint32 => bytes32) public allTaskResponses;

    uint32 private latestTaskNum;
    address private performer;
    address private immutable attestationCenter;
    IOBLS private immutable obls;
    HomeChainCoordinator private immutable homeChainCoordinator;

    // Events
    event PerformerUpdated(address oldPerformer, address newPerformer);
    event NewTaskCreated(uint32 indexed taskIndex, TaskData task);
    // event TaskResponded(TaskResponse taskResponse, TaskResponseMetadata taskResponseMetadata);
    event TaskCompleted(uint32 indexed taskIndex);

    modifier onlyAttestationCenter() {
        require(msg.sender == attestationCenter, "Aggregator must be the caller");
        _;
    }

    // onlyTaskPerformer is used to restrict createNewTask from only being called by a permissioned entity
    // in a real world scenario, this would be removed by instead making createNewTask a payable function
    modifier onlyTaskPerformer() {
        require(msg.sender == performer, "Task performer must be the caller");
        _;
    }

    // TODO: Add governance layer later (and replace the owner with the governance layer)
    constructor(
        address _initialOwner,
        address _performer,
        address _iobls,
        address _attestationCenter,
        address _homeChainCoordinator
    ) Ownable() {
        _transferOwnership(_initialOwner);
        _setPerformer(_performer);
        obls = IOBLS(_iobls);
        attestationCenter = _attestationCenter;
        homeChainCoordinator = HomeChainCoordinator(_homeChainCoordinator);
    }

    function setPerformer(address newPerformer) external onlyOwner {
        _setPerformer(newPerformer);
    }

    /* FUNCTIONS */
    // NOTE: this function creates new task, assigns it a taskId
    function createNewTask(
        bytes32 _blockHash,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _psbtData,
        bytes calldata _options
    ) external onlyTaskPerformer {
        // Store task data
        TaskData memory newTask = TaskData({
            blockHash: _blockHash,
            btcTxnHash: _btcTxnHash,
            proof: _proof,
            index: _index,
            psbtData: _psbtData,
            options: _options
        });
        taskData[latestTaskNum] = newTask;

        // Encode task data hash
        bytes32 taskHash = keccak256(abi.encode(_blockHash, _btcTxnHash, _proof, _index, _psbtData, _options));

        emit NewTaskCreated(latestTaskNum++, newTask);
    }

    // TODO: the signature of the below function needs to change to
    function beforeTaskSubmission(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata _tpSignature,
        uint256[2] calldata _taSignature,
        uint256[] calldata _attestersIds
    ) external onlyAttestationCenter {
        uint32 taskId;
        // check that the task is valid, hasn't been responsed yet
        if (!isTaskValid(taskId)) revert InvalidTask();
        if (isTaskCompleted(taskId)) revert TaskAlreadyCompleted();

        /* CHECKING SIGNATURES & WHETHER THRESHOLD IS MET OR NOT */

        // check the BLS signature
        // (QuorumStakeTotals memory quorumStakeTotals, bytes32 hashOfNonSigners) =
        //     checkSignatures(message, quorumNumbers, taskCreatedBlock, nonSignerStakesAndSignature);

        // // check that signatories own at least a threshold percentage of each quourm
        // for (uint256 i = 0; i < quorumNumbers.length; i++) {
        //     // we don't check that the quorumThresholdPercentages are not >100 because a greater value would trivially fail the check, implying
        //     // signed stake > total stake
        //     require(
        //         quorumStakeTotals.signedStakeForQuorum[i] * _THRESHOLD_DENOMINATOR
        //             >= quorumStakeTotals.totalStakeForQuorum[i] * uint8(quorumThresholdPercentage),
        //         "Signatories do not own at least threshold percentage of a quorum"
        //     );
        // }

        // TaskResponseMetadata memory taskResponseMetadata = TaskResponseMetadata(uint32(block.number), hashOfNonSigners);
        // // updating the storage with task responsea
        // allTaskResponses[taskResponse.referenceTaskIndex] = keccak256(abi.encode(taskResponse, taskResponseMetadata));

        // emitting event
        emit TaskCompleted(taskId);
    }

    function taskNumber() external view returns (uint32) {
        return latestTaskNum;
    }

    function _setPerformer(address newPerformer) internal {
        address oldPerformer = performer;
        performer = newPerformer;
        emit PerformerUpdated(oldPerformer, newPerformer);
    }

    /**
     * @notice Checks if a specific task is completed
     * @param _taskId The task ID to check
     * @return bool True if task is completed
     */
    function isTaskCompleted(uint32 _taskId) public view returns (bool) {
        return completedTasks[_taskId];
    }

    /**
     * @notice Checks if a task is valid by verifying its data exists
     * @param _taskId The task ID to check
     * @return bool True if task exists and is valid
     */
    function isTaskValid(uint32 _taskId) public view returns (bool) {
        TaskData storage task = taskData[_taskId];
        return task.blockHash != bytes32(0) && task.btcTxnHash != bytes32(0);
    }
}
