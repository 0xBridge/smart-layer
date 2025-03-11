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
    address private constant performer = 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE; // TODO: Take this from private key
    address private constant user = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
    address private constant ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;

    // Network configs
    uint256 private sourceForkId;
    uint256 private destForkId;
    HelperConfig.NetworkConfig private srcNetworkConfig;
    HelperConfig.NetworkConfig private destNetworkConfig;

    // Test data
    bytes32 private constant BLOCK_HASH = 0x00000000000078556c00dbcd6505af1b06293da2a2ce4077b36ae0ee7caff284;
    bytes32 private constant BTC_TXN_HASH = 0x0b050a87ba271963ba19dc5ab6a53b6dcf4b5c4f5852033ea92aa78030a9f381;
    bytes32[] private proof;
    uint256 private constant INDEX = 28;
    bytes private constant PSBT_DATA =
        hex"020000000001018b1a4ac7b6fc2a0a58ea6345238faae0785115da71e15b46609caa440ec834b90100000000ffffffff04102700000000000022512038b619797eb282894c5e33d554b03e1bb8d81d6d30d3c1a164ed15c8107f0774e80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144e56a8e3757f167378b38269e1ca0e1a1f124c9e000800000000000003e800040000210500080000000000004e207b84000000000000160014d6a279dc882b830c5562b49e3e25bf3c5767ab7302483045022100b4957432ec426f9f66797305bf0c44d586674d48c260c3d059b81b65a473f717022025b2f1641234dfd3f27eafabdd68a2fa1a0ab286a5292664f7ad9c260aa1455701210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb00000000";
    bytes private constant OPTIONS = hex"0003010011010000000000000000000000000000c350";
    string private constant TAPROOT_ADDRESS = "tb1pk2f9ve04zxjwc9g8m9csvq97ylmer7qpxyr5cmk62uus2dc57vasy6lw4p";
    string private constant NETWORK_KEY = "tb1qk73znvxpcyxzzngmr8gjvwm8jldw86tcv3yrnt";
    address[] private OPERATORS = [
        0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE,
        0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E,
        0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3
    ];

    // Events to test
    event PerformerUpdated(address oldPerformer, address newPerformer);
    event TaskCompleted(bytes32 indexed taskHash);

    function setUp() public {
        string memory rpcUrl = vm.envString("AMOY_RPC_URL");
        sourceForkId = vm.createSelectFork(rpcUrl);
        HelperConfig config = new HelperConfig();
        srcNetworkConfig = config.getConfig();

        string memory destRpcUrl = vm.envString("CORE_TESTNET_RPC_URL");
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
        proof[0] = 0xfb32c9f4cdaba5ea5f3303d3dfe22ac0c309d6af77aace63c68ace550cfedfb1;
        proof[1] = 0x4a678c1094499218f041baabbc196ff021667415939726a39734fa802b3d96aa;
        proof[2] = 0x9acf24b0e1de1e79ef0e7b8a28a5e6d94a3202040f599456ecf7eded81bcc588;
        proof[3] = 0xe288ec65f626692d368a6aff2edf17826424c73cd2489ad4ff83be87e22b293b;
        proof[4] = 0x8b53855e621a58e70554aeb396ca29f2f8b83687011cdd5c6b89dc64f378b358;
        proof[5] = 0xab8ac27bd1f80f1a4e7bf8ab1ba6961647063e6014029f007399e569bed666e5;
        proof[6] = 0x903c0b71cf0d975a2d993437785e412b64c8200a9fb35fd977408259285cec4d;
        proof[7] = 0xa64bb1bdff4ad095eb56d76221ac4393d3217f498e48d9a8f6209e6aa053f884;
        proof[8] = 0x0b01bb3744d2ea2016bdb840f48853cfb6be6321db28320cf44c5172c27eb59b;
        proof[9] = 0xc37d0af040d573fbb7cdba6cd828ee51562fb88158a2e84e6e3cff50c1472be9;

        // Deploy Bitcoin Light Client
        BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
        bytes memory lightClientInitData = abi.encodeWithSelector(
            BitcoinLightClient.initialize.selector,
            owner,
            536870912, // blockVersion
            1738656278, // blockTimestamp
            486604799, // difficultyBits
            4059174314, // nonce
            68741, // height
            0x000000000000123625879059bc5035363bcc5d4dde895f427bbe9b8866d51d7f, // prevBlock
            0x58863b7cb847987c2a0f711e1bb3b910d9a748636c6a7c34cf865ab9ac2048ac // merkleRoot
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
        avsExtension = new AVSExtension(owner, performer, ATTESTATION_CENTER, address(homeChainCoordinator));
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
        emit PerformerUpdated(performer, newPerformer);

        vm.prank(owner);
        avsExtension.setPerformer(newPerformer);
    }

    // TODO: Update the below commented tests
    // function testCreateNewTask() public {
    //     vm.prank(performer);

    //     vm.expectEmit(true, true, true, true);
    //     emit NewTaskCreated(
    //         0,
    //         AVSExtension.TaskData({
    //             blockHash: BLOCK_HASH,
    //             btcTxnHash: BTC_TXN_HASH,
    //             proof: proof,
    //             index: INDEX,
    //             psbtData: PSBT_DATA,
    //             options: OPTIONS
    //         })
    //     );

    //     avsExtension.createNewTask(
    //         BLOCK_HASH, BTC_TXN_HASH, proof, INDEX, PSBT_DATA, OPTIONS, TAPROOT_ADDRESS, NETWORK_KEY, OPERATORS
    //     );

    //     assertEq(avsExtension.taskNumber(), 1);
    // }

    // function testCreateNewTaskNotPerformer() public {
    //     vm.prank(user);
    //     vm.expectRevert(AVSExtension.CallerNotTaskGenerator.selector);

    //     avsExtension.createNewTask(
    //         BLOCK_HASH, BTC_TXN_HASH, proof, INDEX, PSBT_DATA, OPTIONS, TAPROOT_ADDRESS, NETWORK_KEY, OPERATORS
    //     );
    // }

    function testBeforeTaskSubmissionInvalidTask() public {
        bytes32 invalidTaskHash = keccak256("invalid_task");
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
            data: abi.encode(invalidTaskHash),
            taskPerformer: performer,
            taskDefinitionId: 0
        });

        vm.prank(ATTESTATION_CENTER);
        vm.expectRevert(AVSExtension.InvalidTask.selector);

        avsExtension.beforeTaskSubmission(taskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));
    }

    // function testTaskLifecycle() public {
    //     // Create task
    //     vm.prank(performer);
    //     avsExtension.createNewTask(
    //         BLOCK_HASH, BTC_TXN_HASH, proof, INDEX, PSBT_DATA, OPTIONS, TAPROOT_ADDRESS, NETWORK_KEY, OPERATORS
    //     );

    //     bytes32 taskHash = keccak256(abi.encode(BLOCK_HASH, BTC_TXN_HASH, proof, INDEX, PSBT_DATA, OPTIONS));

    //     // Verify task is valid but not completed
    //     assertTrue(avsExtension.isTaskValid(taskHash));
    //     assertFalse(avsExtension.isTaskCompleted(taskHash));

    //     // Simulate task completion through attestation center
    //     IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
    //         proofOfTask: "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP",
    //         data: abi.encode(taskHash),
    //         taskPerformer: performer,
    //         taskDefinitionId: 0
    //     });

    //     vm.prank(ATTESTATION_CENTER);
    //     avsExtension.afterTaskSubmission(taskInfo, true, "", [uint256(0), uint256(0)], new uint256[](0));

    //     // Verify task is now completed
    //     assertTrue(avsExtension.isTaskCompleted(taskHash));
    // }

    function testQuoteGasFees() public {
        (uint256 nativeFee, uint256 lzTokenFee) = avsExtension.quote(BTC_TXN_HASH, PSBT_DATA, OPTIONS, false);

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
