// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {BN254} from "@eigenlayer-middleware/src/libraries/BN254.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {HomeChainCoordinator, PSBTData} from "./HomeChainCoordinator.sol";
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

    bytes32[] internal _taskHashes;
    mapping(bytes32 _taskHash => bool) internal _completedTasks;

    address internal _performer;
    address internal immutable _attestationCenter;
    HomeChainCoordinator internal immutable _homeChainCoordinator;

    // Events
    event PerformerUpdated(address oldPerformer, address newPerformer);
    event NewTaskCreated(bytes32 indexed btcTxnHash);
    event TaskCompleted(bytes32 indexed btcTxnHash);

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
     * @param _isMint Whether the task is a mint or burn
     * @param _blockHash The hash of the Bitcoin block
     * @param _btcTxnHash The hash of the Bitcoin transaction
     * @param _proof The merkle proof for transaction verification
     * @param _index The index of the transaction in the block
     * @param _rawTxn The PSBT data to be processed
     * @param _taprootAddress The taproot address where the btc will be getting locked
     * @param _networkKey The network key for the AVS created from the participated operators
     * @param _operators The addresses of the operators for the network key creation
     * @dev Only the authorized performer can create new tasks
     */
    function createNewTask(
        bool _isMint,
        bytes32 _blockHash,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _rawTxn,
        string calldata _taprootAddress,
        string calldata _networkKey,
        address[] calldata _operators
    ) external onlyTaskPerformer {
        // Create the struct parameter for storeMessage
        HomeChainCoordinator.StoreMessageParams memory params = HomeChainCoordinator.StoreMessageParams({
            isMint: _isMint,
            blockHash: _blockHash,
            btcTxnHash: _btcTxnHash,
            proof: _proof,
            index: _index,
            rawTxn: _rawTxn,
            taprootAddress: _taprootAddress,
            networkKey: _networkKey,
            operators: _operators
        });

        _homeChainCoordinator.storeMessage(params);
        _taskHashes.push(_btcTxnHash);

        emit NewTaskCreated(_btcTxnHash);
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
        bytes32 btcTxnHash = abi.decode(_taskInfo.data, (bytes32));

        // Check that the task is valid, hasn't been responsed yet
        if (!_isApproved) revert TaskNotApproved();
        if (!isTaskValid(btcTxnHash)) revert InvalidTask();
        if (isTaskCompleted(btcTxnHash)) revert TaskAlreadyCompleted();
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
        // Decode task hash (btcTxnHash) from taskInfo data
        (bool txnType, bytes32 btcTxnHash) = abi.decode(_taskInfo.data, (bool, bytes32));

        if (txnType) {
            // Get task data wrt task Id
            PSBTData memory task = _homeChainCoordinator.getPSBTDataForTxnHash(btcTxnHash);

            // Mark task as completed
            _completedTasks[btcTxnHash] = true;

            (uint256 nativeFee,) = quote(btcTxnHash, task.rawTxn, false);
            // Send message after successful verification
            _homeChainCoordinator.sendMessage{value: nativeFee}(btcTxnHash);
        } else {
            _homeChainCoordinator.updateBurnStatus(btcTxnHash);
        }

        // emitting event
        emit TaskCompleted(btcTxnHash);
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
        PSBTData memory task = _homeChainCoordinator.getPSBTDataForTxnHash(_taskHash);
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
        if (_startIndex > _endIndex) revert InvalidTask();

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
