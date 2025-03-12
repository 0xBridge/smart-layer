// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm, console} from "forge-std/Test.sol";
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
    address private constant BTC_RECEIVER = 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE;
    uint256 private constant BTC_AMOUNT = 10000;
    // LayerZero V2 constants
    bytes constant OPTIONS = hex"0003010011010000000000000000000000000000c350";

    // Bitcoin SPV Testnet constants (Block #68738)
    // uint32 private constant blockVersion = 869072896;
    // uint32 private constant blockTimestamp = 1738652675;
    // uint32 private constant difficultyBits = 419705022;
    // uint32 private constant nonce = 3520559627;
    // uint32 private constant height = 68738;
    // bytes32 private constant prevBlock = 0x00000000e6378bc4a8d2271c8a7fcdad607e88efd1ca64c972ca94178fcd8097;
    // bytes32 private constant merkleRoot = 0x929dab60a1e25c777efcebc7121d3be8190894caf884bd2225b34ebcc1261bbf;

    // Bitcoin SPV Testnet constants (Block #72016)
    uint32 private constant blockVersion = 536870912;
    uint32 private constant blockTimestamp = 1740737823;
    uint32 private constant difficultyBits = 486604799;
    uint32 private constant nonce = 1390823984;
    uint32 private constant height = 72016;
    bytes32 private constant prevBlock = 0x0000000000000671792cf513f9ef0c89fec125d9f6f415e4d2f7f799e3bba157;
    bytes32 private constant merkleRoot = 0x322a018a28289a1a6db2c2ce2fd3a9fb013355571a2c6f001c4e3aba6a751edc;

    // AVS Data
    string private constant TAPROOT_ADDRESS = "tb1pk2f9ve04zxjwc9g8m9csvq97ylmer7qpxyr5cmk62uus2dc57vasy6lw4p";
    string private constant NETWORK_KEY = "tb1qk73znvxpcyxzzngmr8gjvwm8jldw86tcv3yrnt";
    address[] private OPERATORS = [
        0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE,
        0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E,
        0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3
    ];

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);

    function setUp() public {
        string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
        sourceForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();

        string memory destRpcUrl = vm.envString("SEPOLIA_RPC_URL");
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
            address(eBTCManagerInstance), // eBTCManager
            destNetworkConfig.chainEid, // chainEid
            srcNetworkConfig.chainEid // HomeChainCoordinator chainEid
        );

        // Deploy implementation and proxy for eBTC using ERC1967Proxy
        eBTC eBTCImplementation = new eBTC();
        bytes memory initData = abi.encodeWithSelector(eBTC.initialize.selector, address(eBTCManagerInstance));
        ERC1967Proxy proxy = new ERC1967Proxy(address(eBTCImplementation), initData);
        eBTCToken = eBTC(address(proxy));

        vm.makePersistent(address(baseChainCoordinator), address(eBTCManagerInstance), address(eBTCToken));

        vm.startPrank(owner);
        eBTCManagerInstance.setBaseChainCoordinator(address(baseChainCoordinator));
        eBTCManagerInstance.setEBTC(address(eBTCToken));
        vm.stopPrank();

        vm.selectFork(sourceForkId);
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
        homeChainCoordinator = new HomeChainCoordinator(
            address(btcLightClient), srcNetworkConfig.endpoint, owner, srcNetworkConfig.chainEid
        );
        vm.makePersistent(address(homeChainCoordinator));

        // Fund the contract
        // vm.deal(address(this), 100 ether);
        vm.deal(owner, 10000 ether); // This is 10000 native tokens on the source chain (POL token has pretty less value when compared to ETH)
    }

    function testSetReceiver() public {
        // Set the receiver
        bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));
        vm.prank(owner);
        homeChainCoordinator.setPeer(destNetworkConfig.chainEid, receiver);

        // Assert that the receiver is set correctly
        assertEq(homeChainCoordinator.peers(destNetworkConfig.chainEid), receiver);
    }

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

        bytes32[] memory proof = new bytes32[](11);
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
        uint256 index = 132;
        // bytes memory type_3_option = abi.encodePacked(uint16(3));
        // bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(type_3_option, 100000, 0);
        bytes32 blockHash = 0x000000000000a20dbeee6d8c5f448e71608e62972c1ff7dd53c567a2df33ff53;
        bytes32 btcTxnHash = 0x63d2189bacdd8f610bce19e493827880bb839019727728ec8f6031b90e2e9e2e;

        bytes memory rawTxn =
            hex"0200000000010172a9903e9c75393c69cd155f4842796b3c52454dad15d83e627749de6c78a7780100000000ffffffff041027000000000000160014b7a229b0c1c10c214d1b19d1263b6797dae3e978e80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a30001471cf07d9c0d8e4bbb5019ccc60437c53fc51e6de00080000000000002710000400009ce100080000000000000000a82a000000000000160014d5a028b62114136a63ebcfacf94e18536b90a1210247304402206d80652d1cc1c6c4b2fe08ae3bdfa2c97121017b07826f7db0a232292c1d74020220579da941457f0d40b93443cf1a223693c59c352a188430f76682d89442918b6d0121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";

        (uint256 nativeFee,) = homeChainCoordinator.quote(btcTxnHash, rawTxn, false);

        vm.recordLogs();
        vm.startPrank(owner);
        homeChainCoordinator.storeMessage(
            true, // isMint,
            blockHash,
            btcTxnHash,
            proof,
            index,
            rawTxn,
            TAPROOT_ADDRESS,
            NETWORK_KEY,
            OPERATORS
        );
        homeChainCoordinator.sendMessage{value: nativeFee}(btcTxnHash);
        vm.stopPrank();

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
