// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {BN254} from "@eigenlayer-middleware/src/libraries/BN254.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {HomeChainCoordinator, PSBTData} from "./HomeChainCoordinator.sol";
import {IAttestationCenter, IAvsLogic} from "./interfaces/IAvsLogic.sol";

/**
 * @title TaskManager
 * @notice Implementation of a secure 0xBridge AVS logic with ownership and pause functionality
 * @dev Responsible for tasks creation and  providing hooks to be called by the attestation center
 */
contract TaskManager is Ownable, Pausable, ReentrancyGuard, IAvsLogic {
    // using BN254 for BN254.G1Point;

    // Errors
    error TaskNotApproved();
    error TaskNotFound();
    error TaskLengthInvalid();
    error InvalidTask(bytes32 taskHash);
    error TaskAlreadyCompleted();
    error InvalidSignatures();
    error CallerNotAttestationCenter();
    error CallerNotTaskGenerator();
    error WithdrawalFailed();
    error NotEnoughGasFee(uint256 gasFee);

    bytes32[] internal _taskHashes;
    mapping(bytes32 _taskHash => bool) internal _completedTasks;

    address internal _taskCreator;
    address internal immutable _attestationCenter;
    HomeChainCoordinator internal immutable _homeChainCoordinator;

    // Events
    event TaskCreatorUpdated(address oldTaskCreator, address newTaskCreator);
    event NewTaskCreated(IAttestationCenter.TaskInfo taskInfo, bytes32 indexed btcTxnHash);
    event TaskCompleted(bool indexed isMintTxn, bytes32 indexed btcTxnHash);

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
     * @notice Ensures the caller is the taskCreator
     * @dev Used to restrict createNewTask from only being called by a permissioned entity
     */
    modifier onlyTaskCreator() {
        if (msg.sender != _taskCreator) {
            revert CallerNotTaskGenerator();
        }
        _;
    }

    /**
     * @notice Initializes the TaskManager contract
     * @param initialOwner_ Address of the initial owner of the contract
     * @param taskCreator_ Address authorized to create new tasks
     * @param attestationCenter_ Address of the attestation center contract
     * @param homeChainCoordinator_ Address of the home chain coordinator contract
     */
    constructor(address initialOwner_, address taskCreator_, address attestationCenter_, address homeChainCoordinator_)
        Ownable()
    {
        _transferOwnership(initialOwner_);
        _setTaskCreator(taskCreator_);
        _attestationCenter = attestationCenter_;
        _homeChainCoordinator = HomeChainCoordinator(payable(homeChainCoordinator_));
    }

    /**
     * @notice Sets a new taskCreator address
     * @param _newTaskCreator The address of the new taskCreator
     * @dev Only callable by the contract owner
     */
    function setTaskCreator(address _newTaskCreator) external onlyOwner {
        _setTaskCreator(_newTaskCreator);
    }

    /**
     * @notice Creates a new task for verification
     * @param _taskInfo The task information struct
     * @param params The parameters for the new task
     * @dev Only the authorized taskCreator can create new tasks
     */
    function createNewTask(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        HomeChainCoordinator.NewTaskParams calldata params
    ) external onlyTaskCreator {
        if (_taskInfo.taskPerformer != msg.sender) revert CallerNotTaskGenerator();
        _homeChainCoordinator.storeMessage(params);
        _taskHashes.push(params.btcTxnHash);

        emit NewTaskCreated(_taskInfo, params.btcTxnHash);
    }

    /**
     * @notice Hook to validate the task details before the task is created in attestation center
     * @param _taskInfo The task information struct
     * @param _isApproved Whether the task is approved
     * @dev The taskCreator's signature (unused but kept for interface compatibility)
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
        (bool isMintTxn, bytes32 btcTxnHash, bytes32 actualTxnHash) =
            abi.decode(_taskInfo.data, (bool, bytes32, bytes32));

        // Check that the task is valid, hasn't been responsed yet
        if (!_isApproved) revert TaskNotApproved();
        if (!isTaskExists(btcTxnHash)) revert InvalidTask(btcTxnHash);
        if (isTaskCompleted(btcTxnHash)) revert TaskAlreadyCompleted();
    }

    /**
     * @notice Hook to validate the task details after the task is created in attestation center
     * @param _taskInfo The task information struct
     * @dev The approval status (unused but kept for interface compatibility)
     * @dev The taskCreator's signature (unused but kept for interface compatibility)
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
        // Decode task hash (btcTxnHash) from taskInfo data
        (bool isMintTxn, bytes32 btcTxnHash, bytes32 actualTxnHash) =
            abi.decode(_taskInfo.data, (bool, bytes32, bytes32));

        // Mark task as completed
        _completedTasks[btcTxnHash] = true;

        if (isMintTxn) {
            // Get task data wrt task Id
            PSBTData memory psbtData = _homeChainCoordinator.getPSBTDataForTxnHash(btcTxnHash);

            (uint256 nativeFee,) = quote(btcTxnHash, psbtData.rawTxn, false);
            console.log("nativeFee", nativeFee);
            // Check if the fee is enough
            if (nativeFee > address(this).balance) revert NotEnoughGasFee(nativeFee);
            _homeChainCoordinator.sendMessage{value: nativeFee}(btcTxnHash);
        } else {
            _homeChainCoordinator.updateBurnStatus(btcTxnHash, actualTxnHash);
        }

        // emitting event
        emit TaskCompleted(isMintTxn, btcTxnHash);
    }

    /**
     * @notice Quotes the gas needed to pay for sending the message
     * @param _btcTxnHash The BTC transaction hash
     * @param _psbtData The PSBT data message to send
     * @param _payInLzToken Boolean for which token to return fee in
     * @return nativeFee Estimated gas fee in native gas
     * @return lzTokenFee Estimated gas fee in ZRO token
     */
    function quote(bytes32 _btcTxnHash, bytes memory _psbtData, bool _payInLzToken)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        (nativeFee, lzTokenFee) = _homeChainCoordinator.quote(_btcTxnHash, _psbtData, _payInLzToken);
    }

    /**
     * @notice Internal function to set the taskCreator address
     * @param _newTaskCreator Address of the new taskCreator
     */
    function _setTaskCreator(address _newTaskCreator) internal {
        address oldTaskCreator = _taskCreator;
        _taskCreator = _newTaskCreator;
        emit TaskCreatorUpdated(oldTaskCreator, _newTaskCreator);
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
    function isTaskExists(bytes32 _taskHash) public view returns (bool) {
        PSBTData memory task = _homeChainCoordinator.getPSBTDataForTxnHash(_taskHash);
        console.logBytes(task.rawTxn);
        return task.rawTxn.length > 0;
    }

    /**
     * @notice Retrieves the data for a specific task
     * @param _taskHash The hash of the task to retrieve
     * @return The task data
     */
    function getTaskData(bytes32 _taskHash) external view returns (PSBTData memory) {
        return _homeChainCoordinator.getPSBTDataForTxnHash(_taskHash);
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

    /**
     * @notice Retrieves the task hashes within a given range
     * @param _startIndex The start index of the task hashes
     * @param _endIndex The end index of the task hashes
     * @return The task hashes within the given range
     */
    function getTaskHashes(uint256 _startIndex, uint256 _endIndex) external view returns (bytes32[] memory) {
        // Check if the start index is greater than the end index
        if (_startIndex > _endIndex) revert TaskLengthInvalid();

        // Check if the end index is greater than the length of the task hashes
        if (_endIndex > _taskHashes.length) revert TaskNotFound();

        // Create a new array to store the task hashes
        bytes32[] memory taskHashes = new bytes32[](_endIndex - _startIndex);

        // Loop through the task hashes and store them in the new array
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            taskHashes[i - _startIndex] = _taskHashes[i];
        }

        return taskHashes;
    }

    /**
     * @notice Retrieves the length of the task hashes array
     * @return The length of the task hashes array
     */
    function getTaskHashesLength() external view returns (uint256) {
        return _taskHashes.length;
    }
}
