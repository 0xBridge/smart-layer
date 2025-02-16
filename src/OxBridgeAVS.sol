// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {BN254} from "@eigenlayer-middleware/src/libraries/BN254.sol";
import {IAttestationCenter, IAvsLogic} from "./interfaces/IAvsLogic.sol";
import {IOBLS} from "./interfaces/IOBLS.sol";

/**
 * @title OxBridgeAVS
 * @dev Implementation of a secure 0xBridge AVS logic with ownership and pause functionality
 */
contract OxBridgeAVS is Ownable, Pausable, ReentrancyGuard, IAvsLogic {
    using BN254 for BN254.G1Point;

    /* CONSTANT */
    // The number of blocks from the task initialization within which the aggregator has to respond to
    uint32 public immutable TASK_RESPONSE_WINDOW_BLOCK;
    uint256 internal constant _THRESHOLD_DENOMINATOR = 100;

    /* STORAGE */
    // The latest task index
    uint32 public latestTaskNum;

    // mapping of task indices to all tasks hashes
    // when a task is created, task hash is stored here,
    // and responses need to pass the actual task,
    // which is hashed onchain and checked against this mapping
    mapping(uint32 => bytes32) public allTaskHashes;

    // mapping of task indices to hash of abi.encode(taskResponse, taskResponseMetadata)
    mapping(uint32 => bytes32) public allTaskResponses;

    mapping(uint32 => bool) public taskSuccesfullyChallenged;

    address private aggregator; // Changes every epoch
    address public performer;

    event PerformerUpdated(address oldPerformer, address newPerformer);
    event AggregatorUpdated(address oldAggregator, address newAggregator);
    event OBLSUpdated(address oldOBLS, address newOBLS);

    modifier onlyAttestationCenter() {
        require(msg.sender == aggregator, "Aggregator must be the caller");
        _;
    }

    // onlyTaskPerformer is used to restrict createNewTask from only being called by a permissioned entity
    // in a real world scenario, this would be removed by instead making createNewTask a payable function
    modifier onlyTaskPerformer() {
        require(msg.sender == performer, "Task performer must be the caller");
        _;
    }

    constructor(
        address initialOwner,
        address _aggregator,
        address _performer,
        IOBLS _iobls,
        uint32 _taskResponseWindowBlock
    ) public {
        _transferOwnership(initialOwner);
        _setAggregator(_aggregator);
        _setPerformer(_performer);
        _setOBLS(_iobls);
        TASK_RESPONSE_WINDOW_BLOCK = _taskResponseWindowBlock;
    }

    function setPerformer(address newPerformer) external onlyOwner {
        _setPerformer(newPerformer);
    }

    function setAggregator(address newAggregator) external onlyOwner {
        _setAggregator(newAggregator);
    }

    /* FUNCTIONS */
    // NOTE: this function creates new task, assigns it a taskId
    function createNewTask(
        string memory aliceSignedPsbt,
        address destinationAddress,
        bytes32 destinationChainCode,
        uint32 quorumThresholdPercentage,
        bytes calldata quorumNumbers
    ) external onlyTaskPerformer {
        // create a new task struct
        Task memory newTask;
        newTask.aliceSignedPsbt = aliceSignedPsbt;
        newTask.destinationAddress = destinationAddress;
        newTask.destinationChainCode = destinationChainCode;
        newTask.taskCreatedBlock = uint32(block.number);
        newTask.quorumThresholdPercentage = quorumThresholdPercentage;
        newTask.quorumNumbers = quorumNumbers;

        // store hash of task onchain, emit event, and increase taskNum
        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        emit NewTaskCreated(latestTaskNum, newTask);
        latestTaskNum = latestTaskNum + 1;
    }

    // TODO: the signature of the below function needs to change to
    function beforeTaskSubmission(
        IAttestationCenter.TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata _tpSignature,
        uint256[2] calldata _taSignature,
        uint256[] calldata _attestersIds
    ) external override onlyAttestationCenter {
        uint32 taskCreatedBlock = task.taskCreatedBlock;
        bytes calldata quorumNumbers = task.quorumNumbers;
        uint32 quorumThresholdPercentage = task.quorumThresholdPercentage;

        // check that the task is valid, hasn't been responsed yet, and is being responsed in time
        require(
            keccak256(abi.encode(task)) == allTaskHashes[taskResponse.referenceTaskIndex],
            "supplied task does not match the one recorded in the contract"
        );
        // some logical checks
        require(
            allTaskResponses[taskResponse.referenceTaskIndex] == bytes32(0),
            "Aggregator has already responded to the task"
        );

        /* CHECKING SIGNATURES & WHETHER THRESHOLD IS MET OR NOT */
        // calculate message which operators signed
        bytes32 message = keccak256(abi.encode(taskResponse));

        // check the BLS signature
        (QuorumStakeTotals memory quorumStakeTotals, bytes32 hashOfNonSigners) =
            checkSignatures(message, quorumNumbers, taskCreatedBlock, nonSignerStakesAndSignature);

        // check that signatories own at least a threshold percentage of each quourm
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            // we don't check that the quorumThresholdPercentages are not >100 because a greater value would trivially fail the check, implying
            // signed stake > total stake
            require(
                quorumStakeTotals.signedStakeForQuorum[i] * _THRESHOLD_DENOMINATOR
                    >= quorumStakeTotals.totalStakeForQuorum[i] * uint8(quorumThresholdPercentage),
                "Signatories do not own at least threshold percentage of a quorum"
            );
        }

        TaskResponseMetadata memory taskResponseMetadata = TaskResponseMetadata(uint32(block.number), hashOfNonSigners);
        // updating the storage with task responsea
        allTaskResponses[taskResponse.referenceTaskIndex] = keccak256(abi.encode(taskResponse, taskResponseMetadata));

        // emitting event
        emit TaskResponded(taskResponse, taskResponseMetadata);
    }

    function taskNumber() external view returns (uint32) {
        return latestTaskNum;
    }

    function getTaskResponseWindowBlock() external view returns (uint32) {
        return TASK_RESPONSE_WINDOW_BLOCK;
    }

    function _setPerformer(address newPerformer) internal {
        address oldPerformer = performer;
        performer = newPerformer;
        emit PerformerUpdated(oldPerformer, newPerformer);
    }

    function _setAggregator(address newAggregator) internal {
        address oldAggregator = aggregator;
        aggregator = newAggregator;
        emit AggregatorUpdated(oldAggregator, newAggregator);
    }

    function _setOBLS(address _iobls) internal {
        address oldOBLS = address(iobls);
        iobls = _iobls;
        emit OBLSUpdated(oldOBLS, _iobls);
    }

    // Should have the option to create, read, done, tasks
    // Should emit relevant events to be listened to by the attesters
    // Should have a function to check if the task is done
    // Should have a function to check if the task is valid
    // Should have a function to check to challenge the task?
}
