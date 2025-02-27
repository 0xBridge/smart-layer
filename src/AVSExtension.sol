// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {BN254} from "@eigenlayer-middleware/src/libraries/BN254.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {HomeChainCoordinator} from "./HomeChainCoordinator.sol";
import {IAttestationCenter, IAvsLogic} from "./interfaces/IAvsLogic.sol";

/**
 * @title AVSExtension
 * @notice Implementation of a secure 0xBridge AVS logic with ownership and pause functionality
 * @dev Manages tasks and processes attestations for bridge operations
 */
contract AVSExtension is Ownable, Pausable, ReentrancyGuard, IAvsLogic {
    // using BN254 for BN254.G1Point;

    // Errors
    error TaskNotApproved();
    error TaskNotFound();
    error InvalidTask();
    error TaskAlreadyCompleted();
    error InvalidSignatures();
    error CallerNotAttestationCenter();
    error CallerNotTaskGenerator();
    error WithdrawalFailed();

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

    mapping(bytes32 taskHash => TaskData) internal _taskData;
    mapping(bytes32 taskHash => bool) internal _completedTasks;

    uint32 internal _latestTaskNum;
    address internal _performer;
    address internal immutable _attestationCenter;
    HomeChainCoordinator internal immutable _homeChainCoordinator;

    // Events
    event PerformerUpdated(address oldPerformer, address newPerformer);
    event NewTaskCreated(uint32 indexed taskIndex, TaskData task);
    event TaskCompleted(bytes32 indexed taskHash);

    /**
     * @notice Ensures the caller is the attestation center
     */
    modifier onlyAttestationCenter() {
        if (msg.sender != _attestationCenter) {
            revert CallerNotAttestationCenter();
        }
        _;
    }

    /**
     * @notice Ensures the caller is the task performer
     * @dev Used to restrict createNewTask from only being called by a permissioned entity
     */
    modifier onlyTaskPerformer() {
        if (msg.sender != _performer) {
            revert CallerNotTaskGenerator();
        }
        _;
    }

    /**
     * @notice Initializes the AVSExtension contract
     * @param initialOwner_ Address of the initial owner of the contract
     * @param performer_ Address authorized to create new tasks
     * @param attestationCenter_ Address of the attestation center contract
     * @param homeChainCoordinator_ Address of the home chain coordinator contract
     */
    constructor(address initialOwner_, address performer_, address attestationCenter_, address homeChainCoordinator_)
        Ownable()
    {
        _transferOwnership(initialOwner_);
        _setPerformer(performer_);
        _attestationCenter = attestationCenter_;
        _homeChainCoordinator = HomeChainCoordinator(payable(homeChainCoordinator_));
    }

    /**
     * @notice Sets a new performer address
     * @param newPerformer The address of the new performer
     * @dev Only callable by the contract owner
     */
    function setPerformer(address newPerformer) external onlyOwner {
        _setPerformer(newPerformer);
    }

    /**
     * @notice Creates a new task for verification
     * @param _blockHash The hash of the Bitcoin block
     * @param _btcTxnHash The hash of the Bitcoin transaction
     * @param _proof The merkle proof for transaction verification
     * @param _index The index of the transaction in the block
     * @param _psbtData The PSBT data to be processed
     * @param _options Additional options for task processing
     * @dev Only the authorized performer can create new tasks
     */
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
        // quorumNumbers: _quorumNumbers,
        // quorumThresholdPct: _quorumThresholdPct

        // Encode task data hash
        bytes32 taskHash = keccak256(abi.encode(_blockHash, _btcTxnHash, _proof, _index, _psbtData, _options));
        _taskData[taskHash] = newTask;

        emit NewTaskCreated(_latestTaskNum++, newTask);
    }

    /**
     * @notice Validates task before submission to the attestation center
     * @param _taskInfo The task information struct
     * @param _isApproved Whether the task is approved
     * @dev The task performer's signature (unused but kept for interface compatibility)
     * @dev The attesters' signature (unused but kept for interface compatibility)
     * @dev The attesters' IDs (unused but kept for interface compatibility)
     * @dev Called by the attestation center before task submission
     */
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

    /**
     * @notice Processes task after submission to the attestation center
     * @param _taskInfo The task information struct
     * @dev The approval status (unused but kept for interface compatibility)
     * @dev The task performer's signature (unused but kept for interface compatibility)
     * @dev The attesters' signature (unused but kept for interface compatibility)
     * @dev The attesters' IDs (unused but kept for interface compatibility)
     * @dev Called by the attestation center after task submission
     */
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
        TaskData memory task = _taskData[taskHash];

        // Mark task as completed
        _completedTasks[taskHash] = true;

        // Quote the gas fee
        (uint256 nativeFee,) = quote(task.btcTxnHash, task.psbtData, task.options, false);
        // Send message after successful verification
        _homeChainCoordinator.sendMessage{value: nativeFee}(
            task.blockHash, task.btcTxnHash, task.proof, task.index, task.psbtData, task.options
        );

        // emitting event
        emit TaskCompleted(taskHash);
    }

    /**
     * @notice Quotes the gas needed to pay for sending the message
     * @param _btcTxnHash The BTC transaction hash
     * @param _psbtData The PSBT data message to send
     * @param _options Message execution options
     * @param _payInLzToken Boolean for which token to return fee in
     * @return nativeFee Estimated gas fee in native gas
     * @return lzTokenFee Estimated gas fee in ZRO token
     */
    function quote(bytes32 _btcTxnHash, bytes memory _psbtData, bytes memory _options, bool _payInLzToken)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        (nativeFee, lzTokenFee) = _homeChainCoordinator.quote(_btcTxnHash, _psbtData, _options, _payInLzToken);
    }

    /**
     * @notice Returns the current task number
     * @return The current task number
     */
    function taskNumber() external view returns (uint32) {
        return _latestTaskNum;
    }

    /**
     * @notice Internal function to set the performer address
     * @param newPerformer Address of the new performer
     */
    function _setPerformer(address newPerformer) internal {
        address oldPerformer = _performer;
        _performer = newPerformer;
        emit PerformerUpdated(oldPerformer, newPerformer);
    }

    /**
     * @notice Checks if a specific task is completed
     * @param _taskHash The task hash to check
     * @return True if task is completed
     */
    function isTaskCompleted(bytes32 _taskHash) public view returns (bool) {
        return _completedTasks[_taskHash];
    }

    /**
     * @notice Checks if a task is valid by verifying its data exists
     * @param _taskHash The task hash to check
     * @return True if task exists and is valid
     */
    function isTaskValid(bytes32 _taskHash) public view returns (bool) {
        TaskData storage task = _taskData[_taskHash];
        return task.blockHash != bytes32(0) && task.btcTxnHash != bytes32(0);
    }

    /**
     * @notice Retrieves the data for a specific task
     * @param _taskHash The hash of the task to retrieve
     * @return The task data
     */
    function getTaskData(bytes32 _taskHash) external view returns (TaskData memory) {
        return _taskData[_taskHash];
    }

    /**
     * @notice Allows receiving ETH
     */
    receive() external payable {}

    /**
     * @notice Fallback function to receive ETH
     */
    fallback() external payable {}

    /**
     * @notice Pauses the contract
     * @dev Only callable by contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Withdraws all ETH from the contract
     * @dev Only callable by contract owner
     */
    function withdraw() external onlyOwner nonReentrant {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert WithdrawalFailed();
    }
}
