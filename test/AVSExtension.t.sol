// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LayerZeroV2Helper} from "lib/pigeon/src/layerzero-v2/LayerZeroV2Helper.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {AVSExtension} from "../src/AVSExtension.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {IAttestationCenter} from "../src/interfaces/IAttestationCenter.sol";
import {eBTCManager} from "../src/eBTCManager.sol";

contract AVSExtensionTest is Test {
    // Main contracts
    AVSExtension private avsExtension;
    HomeChainCoordinator private homeChainCoordinator;
    BaseChainCoordinator private baseChainCoordinator;
    BitcoinLightClient private btcLightClient;
    LayerZeroV2Helper private lzHelper;

    // Test accounts
    address private owner;
    address private constant PERFORMER = 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE; // TODO: Take this from private key
    address private constant USER = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
    address private constant ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;

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
    uint256 private constant INDEX = 131;
    bytes private constant RAW_TXN =
        hex"0200000000010172a9903e9c75393c69cd155f4842796b3c52454dad15d83e627749de6c78a7780100000000ffffffff041027000000000000160014b7a229b0c1c10c214d1b19d1263b6797dae3e978e80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a30001471cf07d9c0d8e4bbb5019ccc60437c53fc51e6de00080000000000002710000400009ce100080000000000000000a82a000000000000160014d5a028b62114136a63ebcfacf94e18536b90a1210247304402206d80652d1cc1c6c4b2fe08ae3bdfa2c97121017b07826f7db0a232292c1d74020220579da941457f0d40b93443cf1a223693c59c352a188430f76682d89442918b6d0121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";

    // AVS Data
    string private constant TAPROOT_ADDRESS = "tb1pk2f9ve04zxjwc9g8m9csvq97ylmer7qpxyr5cmk62uus2dc57vasy6lw4p";
    string private constant NETWORK_KEY = "tb1qk73znvxpcyxzzngmr8gjvwm8jldw86tcv3yrnt";
    address[] private OPERATORS = [
        0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE,
        0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E,
        0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3
    ];

    // Events to test
    event PerformerUpdated(address oldPerformer, address newPerformer);
    event NewTaskCreated(bytes32 indexed btcTxnHash);
    event TaskCompleted(bytes32 indexed btcTxnHash);

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
        proof[0] = 0x20753e310cc491f86ca2f87af292aaceddb7e12773c965c5ce56fb2610b3a85b;
        proof[1] = 0xc91fdeaeec9f532dea4e0d0f175eacad01aa6df5f79fd12eb0cf60a0b45403cc;
        proof[2] = 0x25f944d1fbc29ada8b2fb1e3b844d70f4faefc6e3b437c6357a79c70ecd2ee2f;
        proof[3] = 0x7610680b480d5f26076d4e525c1ab470a4e8383dd2f7423f340f4c18aa9f8321;
        proof[4] = 0xdc5eb091c00510e7df8d46e41947d76fbbd55f814ca4c599238ff5e3ce4d5324;
        proof[5] = 0xe40462e9e50b441bdfa196d11d7464ed2ebe06f10535aa3b18e23cff7bf3c824;
        proof[6] = 0x29c246c61959e3acfbef45f8f6cadedc1c02081cfa2ae7a554f8dae97e025dfd;
        proof[7] = 0x7c53eb3c41a613e70581f8bf478d412904db531281c5a0873af8c2d2d1084d74;
        proof[8] = 0x2cdc8b9432085da444d4f0ce3a7977987f709ed541b05c75c4f30800e0af5597;
        proof[9] = 0x8c1f53dd9d4bc6f03f5af029497e87887f35564be5cbda806dfc98b828d633f9;
        proof[10] = 0x94badf85663bd5b31bf89ea9ffef3a83a4e35665fbc837ee2d03447a53e729ff;

        // Deploy Bitcoin Light Client
        BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
        bytes memory lightClientInitData = abi.encodeWithSelector(
            BitcoinLightClient.initialize.selector,
            owner,
            BLOCK_VERSION,
            BLOCK_TIMESTAMP,
            DIFFICULTY_BITS,
            NONCE,
            HEIGHT,
            PREV_BLOCK,
            MERKLE_ROOT
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

        // Deploy AVSExtension
        avsExtension = new AVSExtension(owner, PERFORMER, ATTESTATION_CENTER, address(homeChainCoordinator));
        // Transfer ownership of HomeChainCoordinator to the avsExtension
        vm.prank(owner);
        homeChainCoordinator.transferOwnership(address(avsExtension));

        // Fund contracts
        vm.deal(owner, 100 ether);
        vm.deal(address(avsExtension), 10 ether);
        vm.deal(address(homeChainCoordinator), 10 ether);

        // lzHelper = new LayerZeroV2Helper();
    }

    function testInitialState() public {
        assertTrue(avsExtension.owner() == owner);
    }

    function testSetPerformer() public {
        address newPerformer = makeAddr("newPerformer");

        vm.expectEmit(true, true, true, true);
        emit PerformerUpdated(PERFORMER, newPerformer);

        vm.prank(owner);
        avsExtension.setPerformer(newPerformer);
    }

    function testCreateNewTask() public {
        uint256 initialTaskHashLength = avsExtension.getTaskHashesLength();

        vm.prank(PERFORMER);
        avsExtension.createNewTask(
            true, BLOCK_HASH, BTC_TXN_HASH, proof, INDEX, RAW_TXN, TAPROOT_ADDRESS, NETWORK_KEY, OPERATORS
        );

        assertEq(avsExtension.getTaskHashesLength(), initialTaskHashLength + 1);
    }

    function testCreateNewTaskNotPerformer() public {
        vm.prank(USER);
        vm.expectRevert(AVSExtension.CallerNotTaskGenerator.selector);
        avsExtension.createNewTask(
            true, BLOCK_HASH, BTC_TXN_HASH, proof, INDEX, RAW_TXN, TAPROOT_ADDRESS, NETWORK_KEY, OPERATORS
        );
    }

    function testBeforeTaskSubmissionInvalidTask() public {
        bytes32 invalidTaskHash = keccak256("invalid_task");
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(invalidTaskHash),
            taskPerformer: PERFORMER,
            taskDefinitionId: 0
        });

        vm.prank(ATTESTATION_CENTER);
        vm.expectRevert(AVSExtension.InvalidTask.selector);

        avsExtension.beforeTaskSubmission(taskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
    }

    function testTaskLifecycle() public {
        // Create task
        vm.prank(PERFORMER);
        avsExtension.createNewTask(
            true, BLOCK_HASH, BTC_TXN_HASH, proof, INDEX, RAW_TXN, TAPROOT_ADDRESS, NETWORK_KEY, OPERATORS
        );

        // Verify task is valid but not completed
        assertTrue(avsExtension.isTaskValid(BTC_TXN_HASH));
        assertFalse(avsExtension.isTaskCompleted(BTC_TXN_HASH));

        // Simulate task completion through attestation center
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(BTC_TXN_HASH),
            taskPerformer: PERFORMER,
            taskDefinitionId: 0
        });

        vm.prank(ATTESTATION_CENTER);
        avsExtension.afterTaskSubmission(taskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));

        // Verify task is now completed
        assertTrue(avsExtension.isTaskCompleted(BTC_TXN_HASH));
    }

    function testQuoteGasFees() public {
        (uint256 nativeFee, uint256 lzTokenFee) = avsExtension.quote(BTC_TXN_HASH, RAW_TXN, false);

        assertTrue(nativeFee > 0);
        assertEq(lzTokenFee, 0); // When payInLzToken is false
    }

    function testPause() public {
        vm.prank(owner);
        avsExtension.pause();
        assertTrue(avsExtension.paused());

        vm.prank(owner);
        avsExtension.unpause();
        assertFalse(avsExtension.paused());
    }

    function testPauseNotOwner() public {
        vm.startPrank(makeAddr("randomUser"));
        vm.expectRevert("Ownable: caller is not the owner");
        avsExtension.pause();
        vm.stopPrank();
    }

    function testWithdraw() public {
        uint256 initialBalance = address(owner).balance;
        uint256 contractBalance = address(avsExtension).balance;

        vm.prank(owner);
        avsExtension.withdraw();

        assertEq(address(owner).balance, initialBalance + contractBalance);
        assertEq(address(avsExtension).balance, 0);
    }

    // receive() external payable {}
}
