// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LayerZeroV2Helper} from "lib/pigeon/src/layerzero-v2/LayerZeroV2Helper.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {eBTCManager} from "../src/eBTCManager.sol";
import {eBTC} from "../src/eBTC.sol";

contract HomeChainCoordinatorTest is Test {
    LayerZeroV2Helper private lzHelper;
    HomeChainCoordinator private homeChainCoordinator;
    BaseChainCoordinator private baseChainCoordinator;
    BitcoinLightClient private btcLightClient;
    eBTCManager private eBTCManagerInstance;
    eBTC private eBTCToken;

    HelperConfig.NetworkConfig private srcNetworkConfig;
    HelperConfig.NetworkConfig private destNetworkConfig;

    address private owner;
    address private user;
    // address private receiver;

    uint256 private sourceForkId;
    uint256 private destForkId;

    // BTC txn metadata
    address private constant BTC_RECEIVER = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
    uint256 private constant BTC_AMOUNT = 1000;

    // Bitcoin SPV Testnet constants (Block #68738)
    // uint32 private constant blockVersion = 869072896;
    // uint32 private constant blockTimestamp = 1738652675;
    // uint32 private constant difficultyBits = 419705022;
    // uint32 private constant nonce = 3520559627;
    // uint32 private constant height = 68738;
    // bytes32 private constant prevBlock = 0x00000000e6378bc4a8d2271c8a7fcdad607e88efd1ca64c972ca94178fcd8097;
    // bytes32 private constant merkleRoot = 0x929dab60a1e25c777efcebc7121d3be8190894caf884bd2225b34ebcc1261bbf;

    // Bitcoin SPV Testnet constants (Block #68741)
    uint32 private constant blockVersion = 536870912;
    uint32 private constant blockTimestamp = 1738656278;
    uint32 private constant difficultyBits = 486604799;
    uint32 private constant nonce = 4059174314;
    uint32 private constant height = 68741;
    bytes32 private constant prevBlock = 0x000000000000123625879059bc5035363bcc5d4dde895f427bbe9b8866d51d7f;
    bytes32 private constant merkleRoot = 0x58863b7cb847987c2a0f711e1bb3b910d9a748636c6a7c34cf865ab9ac2048ac;

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);

    function setUp() public {
        string memory destRpcUrl = vm.envString("CORE_TESTNET_RPC_URL");
        destForkId = vm.createSelectFork(destRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        destNetworkConfig = destConfig.getConfig();
        owner = destNetworkConfig.account;
        vm.prank(owner);

        // Deploy the eBTCManager contract
        eBTCManagerInstance = new eBTCManager(owner);

        // Deploy the base chain coordinator
        baseChainCoordinator = new BaseChainCoordinator(
            destNetworkConfig.endpoint, // endpoint
            owner, // owner
            address(eBTCManagerInstance) // eBTCManager
        );

        // Deploy implementation and proxy for eBTC using ERC1967Proxy
        eBTC eBTCImplementation = new eBTC();
        bytes memory initData = abi.encodeWithSelector(eBTC.initialize.selector, address(eBTCManagerInstance));
        ERC1967Proxy proxy = new ERC1967Proxy(address(eBTCImplementation), initData);
        eBTCToken = eBTC(address(proxy));

        vm.startPrank(owner);
        eBTCManagerInstance.setMinterRole(address(baseChainCoordinator));
        eBTCManagerInstance.setEBTC(address(eBTCToken));
        vm.stopPrank();

        string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
        sourceForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();
        lzHelper = new LayerZeroV2Helper();

        // Deploy implementation and proxy for BitcoinLightClient using ERC1967Proxy
        BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
        bytes memory lightClientInitData = abi.encodeWithSelector(
            BitcoinLightClient.initialize.selector,
            owner,
            blockVersion,
            blockTimestamp,
            difficultyBits,
            nonce,
            height,
            prevBlock,
            merkleRoot
        );
        ERC1967Proxy lightClientProxy = new ERC1967Proxy(address(bitcoinLightClientImplementation), lightClientInitData);
        btcLightClient = BitcoinLightClient(address(lightClientProxy));

        vm.prank(owner);
        homeChainCoordinator = new HomeChainCoordinator(address(btcLightClient), srcNetworkConfig.endpoint, owner);

        // Fund the contract
        // vm.deal(address(this), 100 ether);
        vm.deal(owner, 100 ether); // This is 100 native tokens on the source chain
    }

    function testSetReceiver() public {
        // Set the receiver
        bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));
        vm.prank(owner);
        homeChainCoordinator.setPeer(destNetworkConfig.chainEid, receiver);

        // Assert that the receiver is set correctly
        assertEq(homeChainCoordinator.peers(destNetworkConfig.chainEid), receiver);
    }

    // TODO: Add test for submitBlockAndSendMessage

    function testSendMessage() public {
        // Set the receiver first
        bytes32 sender = bytes32(uint256(uint160(address(homeChainCoordinator))));
        bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));

        // Set receivers and peers on both chains
        vm.selectFork(sourceForkId);
        vm.startPrank(owner);
        homeChainCoordinator.setPeer(destNetworkConfig.chainEid, receiver);
        vm.stopPrank();

        // Set up peer on destination chain
        vm.selectFork(destForkId);
        vm.prank(owner);
        baseChainCoordinator.setPeer(srcNetworkConfig.chainEid, sender);

        // Back to source chain for sending message
        vm.selectFork(sourceForkId);

        bytes32[] memory proof = new bytes32[](10);
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
        uint256 index = 28;
        bytes memory type_3_option = abi.encodePacked(uint16(3));
        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(type_3_option, 100000, 0);
        //     .addExecutorNativeDropOption(200000, 0) // gas limit: 200k, value: 0
        //     .build();
        // bytes memory options = hex"0003010011010000000000000000000000000000c350";
        bytes32 blockHash = 0x00000000000078556c00dbcd6505af1b06293da2a2ce4077b36ae0ee7caff284;
        bytes32 btcTxnHash = 0x0b050a87ba271963ba19dc5ab6a53b6dcf4b5c4f5852033ea92aa78030a9f381;

        bytes memory psbtData =
            hex"020000000001018b1a4ac7b6fc2a0a58ea6345238faae0785115da71e15b46609caa440ec834b90100000000ffffffff04102700000000000022512038b619797eb282894c5e33d554b03e1bb8d81d6d30d3c1a164ed15c8107f0774e80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144e56a8e3757f167378b38269e1ca0e1a1f124c9e000800000000000003e800040000210500080000000000004e207b84000000000000160014d6a279dc882b830c5562b49e3e25bf3c5767ab7302483045022100b4957432ec426f9f66797305bf0c44d586674d48c260c3d059b81b65a473f717022025b2f1641234dfd3f27eafabdd68a2fa1a0ab286a5292664f7ad9c260aa1455701210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb00000000";
        vm.recordLogs();
        vm.prank(owner);
        homeChainCoordinator.sendMessage{value: 1 ether}(blockHash, btcTxnHash, proof, index, psbtData, options);

        // Process the message on destination chain
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(destNetworkConfig.endpoint, destForkId, logs);

        // Check if the message was processed correctly
        vm.selectFork(destForkId);
        // Get eBTC balance of the designated receiver
        uint256 balance = eBTCToken.balanceOf(BTC_RECEIVER);
        assertEq(balance, BTC_AMOUNT);
    }
}
