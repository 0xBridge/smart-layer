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
 * @title AVSExtension
 * @dev Implementation of a secure 0xBridge AVS logic with ownership and pause functionality
 */
contract AVSExtension is Ownable, Pausable, ReentrancyGuard, IAvsLogic {
    // using BN254 for BN254.G1Point;

    // Errors
    error TaskNotApproved();
    error TaskNotFound();
    error InvalidTask();
    error TaskAlreadyCompleted();
    error InvalidSignatures();

    // Constants
    bytes32 internal constant TASK_DOMAIN = keccak256("TasksManager");
    uint16 internal constant TASK_DEFINITION_ID = 1; // For task-specific voting power
    uint32 internal constant DEFAULT_QUORUM_THRESHOLD = 66; // 66% threshold
    uint32 internal constant MINIMUM_QUORUM_NUMBER = 2; // TODO: Change this via governance

    // TODO: Optimize the storage of the below struct
    // Task storage
    struct TaskData {
        bytes32 blockHash;
        bytes32 btcTxnHash;
        bytes32[] proof;
        uint256 index;
        bytes psbtData;
        bytes options;
        bytes quorumNumbers;
        uint32 quorumThresholdPct;
    }

    mapping(uint32 => TaskData) private taskData;
    mapping(uint32 => bool) private completedTasks;

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

    // TODO: Optimis this function
    // NOTE: this function creates new task, assigns it a taskId
    function createNewTask(
        bytes32 _blockHash,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _psbtData,
        bytes calldata _options,
        bytes calldata _quorumNumbers,
        uint32 _quorumThresholdPct
    ) external onlyTaskPerformer {
        // Store task data
        TaskData memory newTask = TaskData({
            blockHash: _blockHash,
            btcTxnHash: _btcTxnHash,
            proof: _proof,
            index: _index,
            psbtData: _psbtData,
            options: _options,
            quorumNumbers: _quorumNumbers,
            quorumThresholdPct: _quorumThresholdPct
        });
        taskData[latestTaskNum] = newTask;

        // Encode task data hash
        bytes32 taskHash = keccak256(abi.encode(_blockHash, _btcTxnHash, _proof, _index, _psbtData, _options));

        emit NewTaskCreated(latestTaskNum++, newTask);
    }

    // TODO: beforeTaskSubmission - check if the task is valid, exists
    function beforeTaskSubmission(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata _tpSignature,
        uint256[2] calldata _taSignature,
        uint256[] calldata _attestersIds
    ) external onlyAttestationCenter {
        // Decode task ID from taskInfo data
        uint32 taskId = abi.decode(_taskInfo.data, (uint32));

        // Check that the task is valid, hasn't been responsed yet
        if (!_isApproved) revert TaskNotApproved();
        if (!isTaskValid(taskId)) revert InvalidTask();
        if (isTaskCompleted(taskId)) revert TaskAlreadyCompleted();

        TaskData memory task = taskData[taskId];

        // Prepare message for signature verification
    }

    function afterTaskSubmission(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata _tpSignature,
        uint256[2] calldata _taSignature,
        uint256[] calldata _attestersIds
    ) external onlyAttestationCenter {
        // Decode task ID from taskInfo data
        uint32 taskId = abi.decode(_taskInfo.data, (uint32));

        // Check that the task is valid, hasn't been responsed yet
        if (!_isApproved) revert TaskNotApproved();
        if (!isTaskValid(taskId)) revert InvalidTask();
        if (isTaskCompleted(taskId)) revert TaskAlreadyCompleted();

        TaskData memory task = taskData[taskId];

        // Prepare message for signature verification
        bytes memory messageBytes = abi.encode(
            taskId,
            task.blockHash,
            task.btcTxnHash,
            task.proof,
            task.index,
            keccak256(task.psbtData),
            keccak256(task.options)
        );

        // Get message point for BLS verification
        uint256[2] memory messagePoint = obls.hashToPoint(TASK_DOMAIN, messageBytes);

        // Calculate required voting power for each quorum
        uint256 requiredPower = 0;
        for (uint256 i = 0; i < task.quorumNumbers.length; i++) {
            uint256 quorumTotalPower = obls.totalVotingPowerPerTaskDefinition(TASK_DEFINITION_ID);
            requiredPower = (quorumTotalPower * task.quorumThresholdPct) / 100;
        }

        // Verify signatures meet quorum
        try obls.verifySignature(
            messagePoint,
            _taSignature,
            _attestersIds,
            requiredPower,
            0 // No minimum per-operator requirement
        ) {
            // TODO: Replace address(this).balance with value from an external function or ZRO token method to to pay the required gas fees
            // TODO: Add a quoteFee function to calculate the required gas fees
            // Send message after successful verification
            homeChainCoordinator.sendMessage{value: address(this).balance}(
                task.blockHash, task.btcTxnHash, task.proof, task.index, task.psbtData, task.options
            );

            // Mark task as completed
            completedTasks[taskId] = true;
            emit TaskCompleted(taskId);
        } catch {
            revert InvalidSignatures();
        }
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

    // Create a getter to fetch the task data
    function getTaskData(uint32 _taskId) external view returns (TaskData memory) {
        return taskData[_taskId];
    }

    // Add receive and fallback functions
    receive() external payable {}

    fallback() external payable {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert("Withdrawal failed");
    }
}
