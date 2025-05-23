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

    // Bitcoin SPV Testnet constants (Block #80169)
    uint32 private constant BLOCK_VERSION = 624918528;
    uint32 private constant BLOCK_TIMESTAMP = 1745999896;
    uint32 private constant DIFFICULTY_BITS = 419821129;
    uint32 private constant NONCE = 183420755;
    uint32 private constant HEIGHT = 80169;
    bytes32 private constant PREV_BLOCK = 0x000000003b4bb24d32b1a5401933e3428188670c18eb8459b147c0575dde8151;
    bytes32 private constant MERKLE_ROOT = 0x70529ffb76a57e9c3a5b29cc6faf0dc8dba0eb4eef82bd9ee70ac1435ad12b2d;

    // Test data
    bytes32 private constant BLOCK_HASH = 0x0000000000000004d815fad54546ee91bca946a5b96ab989fada5fa2c3041e02;
    bytes32 private constant BTC_TXN_HASH = 0xc10ef0ce4ac0cbc7ffffabcc2804e70cc1f332fc29e78d79832d6d67c3b80842;
    bytes32[] private proof;
    uint256 private constant INDEX = 566;
    bytes private constant RAW_TXN =
        hex"02000000000101e48a9f3270ab1ed56b721df9f6dd24af940d23d9c73a9e9bf5a6ac93b2cf15fc0300000000ffffffff041027000000000000225120b2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33be80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144e56a8e3757f167378b38269e1ca0e1a1f124c9e00080000000000002710000400009ca60008000000000000007b8d49000000000000160014d5a028b62114136a63ebcfacf94e18536b90a12102483045022100e36cb24dad4e568561b7a1d00ede31931b624e9698ce020e518bd1cfb9bd895802204b37fd88086672304c3b754e3df32298adcc0bdeebdbf21d7616de027d1b86b10121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";

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

        string memory destRpcUrl = vm.envString("BSC_TESTNET_RPC_URL");
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
        proof = new bytes32[](10);
        proof[0] = 0x1cb1051cb8946953cbf1718560db93260327e25687bdfa4af73edff540059142;
        proof[1] = 0x63dad8c0e19c12bb5b3a7387e2271210116f08922b2823ef5c3ae32e51f14774;
        proof[2] = 0xe50ab33867cc62add8d3e5b98c9bf1b5e623b97ef294e122f56fc63343ecad43;
        proof[3] = 0x2b0a9ea9bbbf8241b7956ea521e607f75ac0e92cd04d3f7669466cf84948eedb;
        proof[4] = 0x7d7119c127bb05cd0a4aba6028f787488aeb24ea1a990ead2cd6275dfff5efed;
        proof[5] = 0xcbc3e46442853ff5b9c1c6727ef238013f4e1f8c75c9a6a87c14b99bb90b25d8;
        proof[6] = 0xdbadf19ed0eeec639c921d29633ea612ba8a0bbf0a5151c33e526423253be677;
        proof[7] = 0x85c70543c75a197d4c96bdd26439bc790756f77a6f8bcd0a1492d6172f852ff0;
        proof[8] = 0x218e3d79150451b7ef119f42ac6e5a16d7ba005d09b4154fe45ba3c336c72c69;
        proof[9] = 0xcaf9ccad2c565ebaf535045d815593b3b0570db93ee4e9a486084a4f68d692e2;

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
        homeChainCoordinator.setTaskSubmitterRole(address(taskManager));
        vm.stopPrank();

        // Fund contracts
        vm.deal(owner, 10 ether);
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
        console.log("Starting testMintTaskLifecycle");
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

        uint256 initialTaskHashLength = taskManager.getTaskHashesLength();
        console.log("Initial task hash length: %s", initialTaskHashLength);

        vm.prank(TASKS_CREATOR);
        taskManager.createNewTask(createTaskInfo, params);
        console.log("Called createNewTask");

        // Verify task is valid but not completed
        bool exists = taskManager.isTaskExists(BTC_TXN_HASH);
        bool completed = taskManager.isTaskCompleted(BTC_TXN_HASH);
        console.log("Task exists: %s", exists);
        console.log("Task completed: %s", completed);
        assertTrue(exists);
        assertFalse(completed);
        console.log("Assertions after createNewTask passed");

        // Simulate task completion through attestation center
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(true, BTC_TXN_HASH, BTC_TXN_HASH),
            taskPerformer: TASKS_CREATOR,
            taskDefinitionId: 0
        });

        // Fund the task manager for gas fees
        vm.deal(address(taskManager), 10 ether);
        console.log("Funded taskManager with 10 ether");

        vm.prank(ATTESTATION_CENTER);
        taskManager.afterTaskSubmission(taskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
        console.log("Called afterTaskSubmission");

        // Verify task is now completed
        bool completedAfter = taskManager.isTaskCompleted(BTC_TXN_HASH);
        uint256 finalTaskHashLength = taskManager.getTaskHashesLength();
        console.log("Task completed after: %s", completedAfter);
        console.log("Final task hash length: %s", finalTaskHashLength);
        assertTrue(completedAfter);
        assertEq(finalTaskHashLength, initialTaskHashLength + 1);
        console.log("testMintTaskLifecycle finished successfully");
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

        uint256 initialTaskHashLength = taskManager.getTaskHashesLength();

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
        assertEq(taskManager.getTaskHashesLength(), initialTaskHashLength + 1);
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
