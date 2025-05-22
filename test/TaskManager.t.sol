// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LayerZeroV2Helper} from "lib/pigeon/src/layerzero-v2/LayerZeroV2Helper.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {IAttestationCenter} from "../src/interfaces/IAttestationCenter.sol";
import {eBTCManager} from "../src/eBTCManager.sol";

contract TaskManagerTest is Test {
    // Main contracts
    TaskManager private taskManager;
    HomeChainCoordinator private homeChainCoordinator;
    BaseChainCoordinator private baseChainCoordinator;
    BitcoinLightClient private btcLightClient;
    LayerZeroV2Helper private lzHelper;

    // Test accounts
    address private owner;
    address private constant TASKS_CREATOR = 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE;
    address private constant USER = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
    address private ATTESTATION_CENTER = 0xC43b825292517d7c0C1f03793460BCda726c6aAA;

    // Network configs
    uint256 private sourceForkId;
    uint256 private destForkId;
    HelperConfig.NetworkConfig private srcNetworkConfig;
    HelperConfig.NetworkConfig private destNetworkConfig;

    // Bitcoin SPV Testnet constants (Block #72016)
    uint32 private constant BLOCK_VERSION = 536870912;
    uint32 private constant BLOCK_TIMESTAMP = 1740737823;
    uint32 private constant DIFFICULTY_BITS = 486604799;
    uint32 private constant NONCE = 1390823984;
    uint32 private constant HEIGHT = 72016;
    bytes32 private constant PREV_BLOCK = 0x0000000000000671792cf513f9ef0c89fec125d9f6f415e4d2f7f799e3bba157;
    bytes32 private constant MERKLE_ROOT = 0x322a018a28289a1a6db2c2ce2fd3a9fb013355571a2c6f001c4e3aba6a751edc;

    // Test data
    bytes32 private constant BLOCK_HASH = 0x000000000000a20dbeee6d8c5f448e71608e62972c1ff7dd53c567a2df33ff53;
    bytes32 private constant BTC_TXN_HASH = 0x63d2189bacdd8f610bce19e493827880bb839019727728ec8f6031b90e2e9e2e;
    bytes32[] private proof;
    uint256 private constant INDEX = 132;
    bytes private constant RAW_TXN =
        hex"0200000000010172a9903e9c75393c69cd155f4842796b3c52454dad15d83e627749de6c78a7780100000000ffffffff041027000000000000160014b7a229b0c1c10c214d1b19d1263b6797dae3e978e80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a30001471cf07d9c0d8e4bbb5019ccc60437c53fc51e6de00080000000000002710000400009ce100080000000000000000a82a000000000000160014d5a028b62114136a63ebcfacf94e18536b90a1210247304402206d80652d1cc1c6c4b2fe08ae3bdfa2c97121017b07826f7db0a232292c1d74020220579da941457f0d40b93443cf1a223693c59c352a188430f76682d89442918b6d0121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";

    // AVS Data
    bytes32 private constant TAPROOT_ADDRESS = 0xb2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33b;
    bytes32 private constant NETWORK_KEY = 0x1a4b83276e5b4ddcf3f7f52615b35c39b013c94f58b941019ddf2be7b511568f;
    address[] private OPERATORS = [
        0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE,
        0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E,
        0xEC1Fa15145c4d27F7e8645F2F68c0E0303AE5690
    ];

    // Events to test
    event TaskCompleted(bool indexed isMintTxn, bytes32 indexed btcTxnHash);

    function setUp() public {
        string memory rpcUrl = vm.envString("AMOY_RPC_URL");
        sourceForkId = vm.createSelectFork(rpcUrl);
        HelperConfig config = new HelperConfig();
        srcNetworkConfig = config.getConfig();

        string memory destRpcUrl = vm.envString("SEPOLIA_RPC_URL");
        destForkId = vm.createSelectFork(destRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        destNetworkConfig = destConfig.getConfig();
        owner = destNetworkConfig.account;

        // Deploy the eBTCManager contract
        eBTCManager eBTCManagerInstance = new eBTCManager(owner);

        // Deploy the base chain coordinator
        baseChainCoordinator = new BaseChainCoordinator(
            destNetworkConfig.endpoint, // endpoint
            owner, // owner
            address(eBTCManagerInstance), // eBTCManager
            destNetworkConfig.chainEid, // chainEid
            srcNetworkConfig.chainEid // HomeChainCoordinator chainEid
        );

        // Switch network to source fork
        vm.selectFork(sourceForkId);

        // Initialize proof array
        proof = new bytes32[](11);
        proof[0] = 0x58e3e27ef80ea9af7cbf6c68414a1a30c4936442fbb78d954763a385b2cf34b4;
        proof[1] = 0x9c60aac47f15333f997af21ef95f91fc170b2cf74550d5537bc0f8b7b268859f;
        proof[2] = 0xfd072d502d65a9621a9cc67bba66d0ebeb8072c38e076cd321201ebc5d0fcf44;
        proof[3] = 0xc7ed53c752b40989e0b28b9a466b7e4d247a3c8c08aa06ff09faddcc89fc1f5c;
        proof[4] = 0xbca34a332518e157bf2bc61d07b9f79a5718306ef9770c9e31d9671c64e0e796;
        proof[5] = 0xb9af329f68773536fea223d8b0733bdce478b19eef448f2c9e777ad0e93c556e;
        proof[6] = 0x745e6898ccd4b8bed3bfe0972d2054ce711696250c6007a4958559dec729ff3e;
        proof[7] = 0xbce49ee30b6ac4361edee0fb70d13d73b4d368080d957747b9e3d76a6ba23915;
        proof[8] = 0x68a804445edf53b793135300e80f45b0160fa4f9dcf1ca6bcf7313ec6b3e4cdd;
        proof[9] = 0x75a385f7ecc1a6c9571b60428cb2f91c0eaf2f88d6396a071cc50dca096d8cb1;
        proof[10] = 0xce78d0c5bcc327d656cab0e8bca278b21d6f3f4438cd57d36b31640efb834e15;

        // Deploy Bitcoin Light Client
        BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
        bytes memory lightClientInitData = abi.encodeCall(
            BitcoinLightClient.initialize,
            (owner, BLOCK_VERSION, BLOCK_TIMESTAMP, DIFFICULTY_BITS, NONCE, HEIGHT, PREV_BLOCK, MERKLE_ROOT)
        );
        ERC1967Proxy lightClientProxy = new ERC1967Proxy(address(bitcoinLightClientImplementation), lightClientInitData);
        btcLightClient = BitcoinLightClient(address(lightClientProxy));
        bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));

        // Deploy HomeChainCoordinator
        vm.startPrank(owner);
        homeChainCoordinator = new HomeChainCoordinator(
            address(btcLightClient), srcNetworkConfig.endpoint, owner, srcNetworkConfig.chainEid
        );
        // Set destination peer address
        homeChainCoordinator.setPeer(destNetworkConfig.chainEid, receiver);
        vm.stopPrank();

        // Deploy TaskManager
        taskManager = new TaskManager(owner, TASKS_CREATOR, ATTESTATION_CENTER, address(homeChainCoordinator));
        // Transfer ownership of HomeChainCoordinator to the taskManager
        vm.startPrank(owner);
        homeChainCoordinator.setTaskGeneratorRole(address(taskManager));
        homeChainCoordinator.setTaskSubmitterRole(ATTESTATION_CENTER);
        homeChainCoordinator.transferOwnership(address(taskManager));
        vm.stopPrank();

        // Fund contracts
        vm.deal(owner, 100 ether);
        vm.deal(address(taskManager), 10 ether);
        // vm.deal(address(homeChainCoordinator), 10 ether);
    }

    function testInitialState() public view {
        assertTrue(taskManager.owner() == owner);
    }

    function testSetTaskCreator() public {
        address newTaskCreator = makeAddr("newTaskCreator");

        vm.expectEmit(true, true, true, true);
        emit TaskManager.TaskCreatorUpdated(TASKS_CREATOR, newTaskCreator);

        vm.prank(owner);
        taskManager.setTaskCreator(newTaskCreator);
    }

    function testCreateNewTask() public {
        uint256 initialTaskHashLength = taskManager.getTaskHashesLength();

        // Create task params struct
        HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams({
            isMintTxn: true,
            blockHash: BLOCK_HASH,
            btcTxnHash: BTC_TXN_HASH,
            proof: proof,
            index: INDEX,
            rawTxn: RAW_TXN,
            taprootAddress: TAPROOT_ADDRESS,
            networkKey: NETWORK_KEY,
            operators: OPERATORS
        });

        // Create TaskInfo struct
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(true, BTC_TXN_HASH, BTC_TXN_HASH),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        // Setup event expectation
        vm.expectEmit(true, true, true, true);
        emit TaskManager.NewTaskCreated(taskInfo, BTC_TXN_HASH);

        // Execute the function
        vm.prank(TASKS_CREATOR);
        taskManager.createNewTask(taskInfo, params);

        // Assert that task hash length increased
        assertEq(taskManager.getTaskHashesLength(), initialTaskHashLength + 1);

        // Assert that the task exists
        assertTrue(taskManager.isTaskExists(BTC_TXN_HASH));

        // Assert that the task is not completed yet
        assertFalse(taskManager.isTaskCompleted(BTC_TXN_HASH));
    }

    function testCreateNewTaskNotTaskCreator() public {
        // Create task params struct
        HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams({
            isMintTxn: true,
            blockHash: BLOCK_HASH,
            btcTxnHash: BTC_TXN_HASH,
            proof: proof,
            index: INDEX,
            rawTxn: RAW_TXN,
            taprootAddress: TAPROOT_ADDRESS,
            networkKey: NETWORK_KEY,
            operators: OPERATORS
        });

        // Create TaskInfo struct
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(true, BTC_TXN_HASH, BTC_TXN_HASH),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        vm.prank(USER);
        vm.expectRevert(TaskManager.CallerNotTaskGenerator.selector);
        taskManager.createNewTask(taskInfo, params);
    }

    function testBeforeTaskSubmissionInvalidTask() public {
        bytes32 invalidTaskHash = keccak256("invalid_task");
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(true, invalidTaskHash, BTC_TXN_HASH),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        vm.prank(ATTESTATION_CENTER);
        vm.expectRevert(abi.encodeWithSelector(TaskManager.InvalidTask.selector, invalidTaskHash));
        taskManager.beforeTaskSubmission(taskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
    }

    function testBeforeTaskSubmissionValid() public {
        // First create a task
        HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams({
            isMintTxn: true,
            blockHash: BLOCK_HASH,
            btcTxnHash: BTC_TXN_HASH,
            proof: proof,
            index: INDEX,
            rawTxn: RAW_TXN,
            taprootAddress: TAPROOT_ADDRESS,
            networkKey: NETWORK_KEY,
            operators: OPERATORS
        });

        // Create TaskInfo struct
        IAttestationCenter.TaskInfo memory createTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(true, BTC_TXN_HASH, BTC_TXN_HASH),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        vm.prank(TASKS_CREATOR);
        taskManager.createNewTask(createTaskInfo, params);

        // Now try beforeTaskSubmission with the valid task
        IAttestationCenter.TaskInfo memory submissionTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(true, BTC_TXN_HASH, BTC_TXN_HASH),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        // This should not revert if the task is valid
        vm.prank(ATTESTATION_CENTER);
        taskManager.beforeTaskSubmission(submissionTaskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
    }

    function testMintTaskLifecycle() public {
        // Create task
        HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams({
            isMintTxn: true,
            blockHash: BLOCK_HASH,
            btcTxnHash: BTC_TXN_HASH,
            proof: proof,
            index: INDEX,
            rawTxn: RAW_TXN,
            taprootAddress: TAPROOT_ADDRESS,
            networkKey: NETWORK_KEY,
            operators: OPERATORS
        });

        // Create TaskInfo struct
        IAttestationCenter.TaskInfo memory createTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(true, BTC_TXN_HASH, BTC_TXN_HASH),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        vm.prank(TASKS_CREATOR);
        taskManager.createNewTask(createTaskInfo, params);

        // Verify task is valid but not completed
        assertTrue(taskManager.isTaskExists(BTC_TXN_HASH));
        assertFalse(taskManager.isTaskCompleted(BTC_TXN_HASH));

        // Simulate task completion through attestation center
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(true, BTC_TXN_HASH, BTC_TXN_HASH),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        // Expect the TaskCompleted event to be emitted
        vm.expectEmit(true, true, true, true);
        emit TaskCompleted(true, BTC_TXN_HASH);

        // Fund the task manager for gas fees
        vm.deal(address(taskManager), 1 ether);

        vm.prank(ATTESTATION_CENTER);
        taskManager.afterTaskSubmission(taskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));

        // Verify task is now completed
        assertTrue(taskManager.isTaskCompleted(BTC_TXN_HASH));
    }

    function testBurnTaskLifecycle() public {
        // Create a burn task
        bytes32[] memory burnProof = new bytes32[](0);
        HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams({
            isMintTxn: false,
            blockHash: BLOCK_HASH,
            btcTxnHash: BTC_TXN_HASH,
            proof: burnProof,
            index: 0,
            rawTxn: RAW_TXN,
            taprootAddress: TAPROOT_ADDRESS,
            networkKey: NETWORK_KEY,
            operators: OPERATORS
        });

        // Create TaskInfo struct
        IAttestationCenter.TaskInfo memory createTaskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(false, BTC_TXN_HASH, BTC_TXN_HASH),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        vm.prank(TASKS_CREATOR);
        taskManager.createNewTask(createTaskInfo, params);

        // Verify task is valid but not completed
        assertTrue(taskManager.isTaskExists(BTC_TXN_HASH));
        assertFalse(taskManager.isTaskCompleted(BTC_TXN_HASH));

        // Simulate task completion through attestation center
        bytes32 actualTxnHash = keccak256("actual_txn_hash");
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(false, BTC_TXN_HASH, actualTxnHash),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        // Expect the TaskCompleted event to be emitted
        vm.expectEmit(true, true, true, true);
        emit TaskCompleted(false, BTC_TXN_HASH);

        vm.prank(ATTESTATION_CENTER);
        taskManager.afterTaskSubmission(taskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));

        // Verify task is now completed
        assertTrue(taskManager.isTaskCompleted(BTC_TXN_HASH));
    }

    function testGetTaskHashes() public {
        // Create multiple tasks
        for (uint256 i = 0; i < 3; i++) {
            bytes32 btcTxnHash = keccak256(abi.encode("task", i));

            HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams({
                isMintTxn: true,
                blockHash: BLOCK_HASH,
                btcTxnHash: btcTxnHash,
                proof: proof,
                index: INDEX,
                rawTxn: RAW_TXN,
                taprootAddress: TAPROOT_ADDRESS,
                networkKey: NETWORK_KEY,
                operators: OPERATORS
            });

            IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
                proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
                data: abi.encode(true, btcTxnHash, btcTxnHash),
                taskPerformer: TASKS_CREATOR,
                taskDefinitionId: 0
            });

            vm.prank(TASKS_CREATOR);
            taskManager.createNewTask(taskInfo, params);
        }

        // Get task hashes from index 0 to 2
        bytes32[] memory taskHashes = taskManager.getTaskHashes(0, 2);

        // Verify the length
        assertEq(taskHashes.length, 2);
    }

    function testQuoteGasFees() public view {
        (uint256 nativeFee, uint256 lzTokenFee) = taskManager.quote(BTC_TXN_HASH, RAW_TXN, false);

        assertTrue(nativeFee > 0);
        assertEq(lzTokenFee, 0); // When payInLzToken is false
    }

    function testPause() public {
        vm.prank(owner);
        taskManager.pause();
        assertTrue(taskManager.paused());

        vm.prank(owner);
        taskManager.unpause();
        assertFalse(taskManager.paused());
    }

    function testPauseNotOwner() public {
        vm.startPrank(makeAddr("randomUser"));
        vm.expectRevert("Ownable: caller is not the owner");
        taskManager.pause();
        vm.stopPrank();
    }

    function testWithdraw() public {
        uint256 initialBalance = address(owner).balance;
        uint256 contractBalance = address(taskManager).balance;

        vm.prank(owner);
        taskManager.withdraw();

        assertEq(address(owner).balance, initialBalance + contractBalance);
        assertEq(address(taskManager).balance, 0);
    }

    receive() external payable {}
}
