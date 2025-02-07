// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {BLSApkRegistry} from "@eigenlayer-middleware/src/BLSApkRegistry.sol";
import {RegistryCoordinator} from "@eigenlayer-middleware/src/RegistryCoordinator.sol";
import {BLSSignatureChecker, IRegistryCoordinator} from "@eigenlayer-middleware/src/BLSSignatureChecker.sol";
import {OperatorStateRetriever} from "@eigenlayer-middleware/src/OperatorStateRetriever.sol";
import {BN254} from "@eigenlayer-middleware/src/libraries/BN254.sol";
import {
    Pausable,
    IPauserRegistry
} from "lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/permissions/Pausable.sol";

/**
 * @title AVSTaskManager
 * @dev Manages tasks and operator quorums for an Actively Validated Service (AVS)
 * @notice This contract integrates with EigenLayer for operator management and BLS signature verification
 */
contract AVSTaskManager is Initializable, OwnableUpgradeable, Pausable, BLSSignatureChecker, OperatorStateRetriever {
    using BN254 for BN254.G1Point;

    /* CONSTANTS */
    uint32 public immutable TASK_RESPONSE_WINDOW_BLOCK;
    uint32 public constant TASK_CHALLENGE_WINDOW_BLOCK = 100;
    uint256 internal constant _THRESHOLD_DENOMINATOR = 100;

    /* STRUCTURES */
    struct Task {
        bytes32 taskHash;
        uint32 taskCreatedBlock;
        uint32 quorumThresholdPercentage;
        bytes quorumNumbers;
        bool isCompleted;
    }

    struct TaskResponse {
        uint32 referenceTaskIndex;
        bytes32 response;
    }

    struct TaskResponseMetadata {
        uint32 taskResponsedBlock;
        bytes32 hashOfNonSigners;
    }

    // struct NonSignerStakesAndSignature {
    //     uint256[] nonSignerQuorumStakeAmounts;
    //     BN254.G1Point[] nonSignerPubkeys;
    //     BN254.G2Point signature;
    // }

    /* STATE VARIABLES */
    uint32 public latestTaskNum;
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(uint32 => bytes32) public allTaskResponses;
    mapping(uint32 => bool) public taskSuccesfullyChallenged;
    mapping(address => bool) public isOperator;

    address public aggregator;
    address public generator;

    /* EVENTS */
    event NewTaskCreated(uint32 indexed taskId, Task task);
    event TaskResponded(TaskResponse taskResponse, TaskResponseMetadata metadata);
    event TaskChallengedSuccessfully(uint32 indexed taskId, address indexed challenger);
    event TaskChallengedUnsuccessfully(uint32 indexed taskId, address indexed challenger);
    event GeneratorUpdated(address indexed oldGenerator, address indexed newGenerator);
    event AggregatorUpdated(address indexed oldAggregator, address indexed newAggregator);
    event OperatorStatusChanged(address indexed operator, bool status);

    /* MODIFIERS */
    modifier onlyOperator() {
        require(isOperator[msg.sender], "Operator only");
        _;
    }

    /* CONSTRUCTOR */
    constructor(IRegistryCoordinator _registryCoordinator, uint32 _taskResponseWindowBlock)
        BLSSignatureChecker(_registryCoordinator)
    {
        TASK_RESPONSE_WINDOW_BLOCK = _taskResponseWindowBlock;
    }

    /**
     * @dev Initialize the contract
     * @param _pauserRegistry Pauser registry contract
     * @param initialOwner Initial owner of the contract
     * @param _initialOperators Initial generator address
     */
    function initialize(IPauserRegistry _pauserRegistry, address initialOwner, address[] memory _initialOperators)
        public
        initializer
    {
        _initializePauser(_pauserRegistry, UNPAUSE_ALL);
        _transferOwnership(initialOwner);
        _initialiseOperators(_initialOperators);
    }

    function _initialiseOperators(address[] memory _initialOperators) internal {
        for (uint256 i = 0; i < _initialOperators.length; i++) {
            _setOperator(_initialOperators[i], true);
        }
    }

    function setOperators(address[] calldata _operator, bool[] calldata _statuses) external onlyOwner {
        require(_operator.length == _statuses.length, "Invalid input");
        for (uint256 i = 0; i < _operator.length; i++) {
            _setOperator(_operator[i], _statuses[i]);
        }
    }

    function _setOperator(address _operator, bool _status) internal {
        isOperator[_operator] = _status;
        emit OperatorStatusChanged(_operator, _status);
    }

    /**
     * @dev Creates a new task
     * @param taskData Task data to be hashed
     * @param quorumThresholdPercentage Required percentage of quorum participation
     * @param quorumNumbers Quorum identifiers
     */
    function createNewTask(bytes calldata taskData, uint32 quorumThresholdPercentage, bytes calldata quorumNumbers)
        external
        onlyOperator
    {
        Task memory newTask;
        newTask.taskHash = keccak256(taskData);
        newTask.taskCreatedBlock = uint32(block.number);
        newTask.quorumThresholdPercentage = quorumThresholdPercentage;
        newTask.quorumNumbers = quorumNumbers;
        newTask.isCompleted = false;

        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        emit NewTaskCreated(latestTaskNum, newTask);
        latestTaskNum = latestTaskNum + 1;
    }

    /**
     * @dev Responds to an existing task with aggregated signature
     * @param task Original task data
     * @param taskResponse Response data
     * @param nonSignerStakesAndSignature Signature and stake information
     */
    function respondToTask(
        Task calldata task,
        TaskResponse calldata taskResponse,
        NonSignerStakesAndSignature memory nonSignerStakesAndSignature
    ) external onlyOperator {
        require(keccak256(abi.encode(task)) == allTaskHashes[taskResponse.referenceTaskIndex], "Task mismatch");
        require(allTaskResponses[taskResponse.referenceTaskIndex] == bytes32(0), "Task already responded");
        require(uint32(block.number) <= task.taskCreatedBlock + TASK_RESPONSE_WINDOW_BLOCK, "Response window expired");

        // Calculate message hash for signature verification
        bytes32 message = keccak256(abi.encode(taskResponse));

        // Verify BLS signature and check quorum thresholds
        (QuorumStakeTotals memory quorumStakeTotals, bytes32 hashOfNonSigners) =
            checkSignatures(message, task.quorumNumbers, task.taskCreatedBlock, nonSignerStakesAndSignature);

        // Verify quorum threshold requirements
        for (uint256 i = 0; i < task.quorumNumbers.length; i++) {
            require(
                quorumStakeTotals.signedStakeForQuorum[i] * _THRESHOLD_DENOMINATOR
                    >= quorumStakeTotals.totalStakeForQuorum[i] * uint8(task.quorumThresholdPercentage),
                "Quorum threshold not met"
            );
        }

        TaskResponseMetadata memory metadata = TaskResponseMetadata(uint32(block.number), hashOfNonSigners);

        allTaskResponses[taskResponse.referenceTaskIndex] = keccak256(abi.encode(taskResponse, metadata));

        emit TaskResponded(taskResponse, metadata);
    }

    /**
     * @dev Returns the total number of tasks
     */
    function taskNumber() external view returns (uint32) {
        return latestTaskNum;
    }

    /**
     * @dev Returns the task response window in blocks
     */
    function getTaskResponseWindowBlock() external view returns (uint32) {
        return TASK_RESPONSE_WINDOW_BLOCK;
    }

    /**
     * @dev Internal function to update generator address
     */
    function _setGenerator(address newGenerator) internal {
        address oldGenerator = generator;
        generator = newGenerator;
        emit GeneratorUpdated(oldGenerator, newGenerator);
    }

    /**
     * @dev Internal function to update aggregator address
     */
    function _setAggregator(address newAggregator) internal {
        address oldAggregator = aggregator;
        aggregator = newAggregator;
        emit AggregatorUpdated(oldAggregator, newAggregator);
    }
}
