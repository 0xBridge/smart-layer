// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {BN254} from "@eigenlayer-middleware/src/libraries/BN254.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
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
    }
    // bytes quorumNumbers;
    // uint32 quorumThresholdPct;

    mapping(bytes32 taskHash => TaskData) private taskData;
    mapping(bytes32 taskHash => bool) private completedTasks;

    uint32 private latestTaskNum;
    address private performer;
    address private immutable attestationCenter;
    IOBLS private immutable obls;
    HomeChainCoordinator private immutable homeChainCoordinator;

    // Events
    event PerformerUpdated(address oldPerformer, address newPerformer);
    event NewTaskCreated(uint32 indexed taskIndex, TaskData task);
    // event TaskResponded(TaskResponse taskResponse, TaskResponseMetadata taskResponseMetadata);
    event TaskCompleted(bytes32 indexed taskHash);

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
        homeChainCoordinator = HomeChainCoordinator(payable(_homeChainCoordinator));
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
        bytes calldata _options
    )
        // bytes calldata _quorumNumbers,
        // uint32 _quorumThresholdPct
        external
        onlyTaskPerformer
    {
        // Store task data
        TaskData memory newTask = TaskData({
            blockHash: _blockHash,
            btcTxnHash: _btcTxnHash,
            proof: _proof,
            index: _index,
            psbtData: _psbtData,
            options: _options
        });
        // quorumNumbers: _quorumNumbers,
        // quorumThresholdPct: _quorumThresholdPct

        // Encode task data hash
        bytes32 taskHash = keccak256(abi.encode(_blockHash, _btcTxnHash, _proof, _index, _psbtData, _options));
        taskData[taskHash] = newTask;

        emit NewTaskCreated(latestTaskNum++, newTask);
    }

    // TODO: beforeTaskSubmission - check if the task is valid, exists
    function beforeTaskSubmission(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata,
        uint256[2] calldata,
        uint256[] calldata
    ) external view onlyAttestationCenter {
        // Decode task hash from taskInfo data
        bytes32 taskHash = abi.decode(_taskInfo.data, (bytes32));

        // Check that the task is valid, hasn't been responsed yet
        if (!_isApproved) revert TaskNotApproved();
        if (!isTaskValid(taskHash)) revert InvalidTask();
        if (isTaskCompleted(taskHash)) revert TaskAlreadyCompleted();
    }

    function afterTaskSubmission(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        bool,
        bytes calldata,
        uint256[2] calldata,
        uint256[] calldata
    ) external onlyAttestationCenter {
        // Decode task hash from taskInfo data
        bytes32 taskHash = abi.decode(_taskInfo.data, (bytes32));

        // Get task data wrt task Id
        TaskData memory task = taskData[taskHash];

        // Mark task as completed
        completedTasks[taskHash] = true;

        // Quote the gas fee
        (uint256 nativeFee,) = quote(task.btcTxnHash, task.psbtData, task.options, false);
        // Send message after successful verification
        homeChainCoordinator.sendMessage{value: nativeFee}(
            task.blockHash, task.btcTxnHash, task.proof, task.index, task.psbtData, task.options
        );

        // emitting event
        emit TaskCompleted(taskHash);
    }

    /* @dev Quotes the gas needed to pay for the sending the message of btcTxnHash
    /* @param _btcTxnHash The BTC transaction hash
    /* @param _psbtData The _psbtData message to send
    /* @param _options Message execution options
    /* @param _payInLzToken boolean for which token to return fee in
    * @return nativeFee Estimated gas fee in native gas.
    * @return lzTokenFee Estimated gas fee in ZRO token.
    */
    function quote(
        bytes32 _btcTxnHash, // The BTC transaction hash
        bytes memory _psbtData, // The _psbtData message to send
        bytes memory _options, // Message execution options
        bool _payInLzToken // boolean for which token to return fee in
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        (nativeFee, lzTokenFee) = homeChainCoordinator.quote(_btcTxnHash, _psbtData, _options, _payInLzToken);
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
     * @param _taskHash The task hash to check
     * @return bool True if task is completed
     */
    function isTaskCompleted(bytes32 _taskHash) public view returns (bool) {
        return completedTasks[_taskHash];
    }

    /**
     * @notice Checks if a task is valid by verifying its data exists
     * @param _taskHash The task hash to check
     * @return bool True if task exists and is valid
     */
    function isTaskValid(bytes32 _taskHash) public view returns (bool) {
        TaskData storage task = taskData[_taskHash];
        return task.blockHash != bytes32(0) && task.btcTxnHash != bytes32(0);
    }

    function getTaskData(bytes32 _taskHash) external view returns (TaskData memory) {
        return taskData[_taskHash];
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
