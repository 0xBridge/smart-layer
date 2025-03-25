// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LayerZeroV2Helper} from "lib/pigeon/src/layerzero-v2/LayerZeroV2Helper.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {HomeChainCoordinator, PSBTData} from "../src/HomeChainCoordinator.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {eBTCManager} from "../src/eBTCManager.sol";
import {eBTC} from "../src/eBTC.sol";
import {TxidCalculator} from "../src/libraries/TxidCalculator.sol";

contract HomeChainCoordinatorTest is Test {
    LayerZeroV2Helper private lzHelper;
    LayerZeroV2Helper private burnLzHelper;
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

    uint256 private srcForkId;
    uint256 private destForkId;

    // BTC txn metadata
    address private constant BTC_RECEIVER = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
    uint256 private constant BTC_AMOUNT = 1357;

    // Bitcoin SPV Testnet constants for MINT (Block #72979)
    uint32 private constant MINT_BLOCK_VERSION = 536870912;
    uint32 private constant MINT_BLOCK_TIMESTAMP = 1741357556;
    uint32 private constant MINT_DIFFICULTY_BITS = 486604799;
    uint32 private constant MINT_NONCE = 3368467969;
    uint32 private constant MINT_HEIGHT = 72979;
    bytes32 private constant MINT_PREV_BLOCK = 0x0000000002e46dca25f7aef5a8181f2d44357259c1f317e95e9039b0b88665bd;
    bytes32 private constant MINT_MERKLE_ROOT = 0x4f78f364779d441318a19ac8324c38859684e30c62c604f944cf08a82ea6a40f;

    bytes32 private constant MINT_BLOCK_HASH = 0x000000008616134584b18a2e16e2b6f4b6f8acc7a1a975c2a8c6f8b10493e260;
    bytes32 private constant MINT_BTC_TXN_HASH = 0xbde7e25aa0177ddc3f35b9d35fe87ee4d6d48125527f4a7a67257b272d517d13;
    bytes MINT_RAW_TXN =
        hex"020000000001022e9e2e0eb931608fec287772199083bb80788293e419ce0b618fddac9b18d2630300000000ffffffff086377c5c4961ec2bb4b5164e7644df437cceb42114270cfe2df7b0e9d0135390300000000ffffffff041027000000000000225120b2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33be80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144e56a8e3757f167378b38269e1ca0e1a1f124c9e0008000000000000054d000400009ca60008000000000000007bf316000000000000160014d5a028b62114136a63ebcfacf94e18536b90a12102483045022100a8b08ad91a4318a12078e76eb40d2f24d2bfa5d1c10aec4664cd86e84fb231ba02201854324af6e39c05998d73ae212e82dcf0a440af620b0a78f19e7e0387b3104f0121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250602473044022054d62f5034de4e947911617c4b878894060c6be37a5b97fa0583a966d10781fe022046d2440c4644475cf9603b5b782154f083ce2f8d0ce3cb4b1ece1f884cf8428f0121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";

    // Bitcoin SPV Testnet constants for Mint (Block #72980)
    uint32 private constant BURN_BLOCK_VERSION = 634445824;
    uint32 private constant BURN_BLOCK_TIMESTAMP = 1741351552;
    uint32 private constant BURN_DIFFICULTY_BITS = 419717576;
    uint32 private constant BURN_NONCE = 524461350;
    uint32 private constant BURN_HEIGHT = 72980;
    bytes32 private constant BURN_PREV_BLOCK = 0x000000008616134584b18a2e16e2b6f4b6f8acc7a1a975c2a8c6f8b10493e260;
    bytes32 private constant BURN_MERKLE_ROOT = 0xa651b501d7ac0387534c9bbd29e2585197d2fd2312d8aa17e0b75dce7deb4c0e;

    bytes BURN_BLOCK_HEADER =
        hex"00e0d02560e29304b1f8c6a8c275a9a1c7acf8b6f4b6e2162e8ab18445131686000000000e4ceb7dce5db7e017aad81223fdd2975158e229bd9b4c538703acd701b551a680eaca67c861041926a5421f";
    bytes32 private constant BURN_BLOCK_HASH = 0x00000000000000022ada2600b6c909cb30c02520a66b55387159a20f1bb924d6;
    bytes32 private constant BURN_BTC_TXN_HASH = 0xfe38ee746989f4372ed260bbc8bfc41ebb7108d714789574aba2057ce8c7bde0;
    bytes BURN_RAW_TXN =
        hex"02000000000102137d512d277b25677a4a7f522581d4d6e47ee85fd3b9353fdc7d17a05ae2e7bd0000000000ffffffff9e504ef8a97d1c29c8df3db5e79fdc2dc362d2d770c66e234a849b915a449e1d0000000000ffffffff028813000000000000160014cf54150aff704eb4ecae400d9e665eb285dcbfaff40100000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10440e0c768d0f30cb9617d4e89a4887be7515a8be186478b2c6554fc8701e04f0f72bd5882710156aed605365c4f74b4b7f767d7ffc2d9730a3c220208bc892f62c44022d47f4bc506a5d4df5263471db65697ad5b74573cd98f534f7ad2dcd2227deaaf1ace3e6186a3d634ffa9ea657a71d39b4b441e9c8b477c2ab9ddde7542e92c44206a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb2506ad201a4b83276e5b4ddcf3f7f52615b35c39b013c94f58b941019ddf2be7b511568fac41c16a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb25061c38128ccf96002c3f5ce0e3b9d4d587a7744ba51e4814c2b2569b89cf09640704408efafc4f08a1c4780daac0990190485025ce8f8443f5297fbdcd3f45e5f0d1fb4817b104e961b42a56ed71a2b43616aa0a62298e5a2a248e713b079f31b88a1d40018bb141f298e78962c25930c554c778978782e5e2627d602131ba99a3c27458b7f51d8c67b22fdc02fac7f3467c7fa5fcd1741041a1b5645a497c92a905b06e44206a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb2506ad201a4b83276e5b4ddcf3f7f52615b35c39b013c94f58b941019ddf2be7b511568fac41c16a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb25061c38128ccf96002c3f5ce0e3b9d4d587a7744ba51e4814c2b2569b89cf09640700000000";

    // AVS Data (Dummy values)
    bytes32 private constant TAPROOT_ADDRESS = 0xb2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33b;
    bytes32 private constant NETWORK_KEY = 0xb7a229b0c1c10c214d1b19d1263b6797dae3e978000000000000000000000000;
    address[] private OPERATORS = [
        0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE,
        0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E,
        0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3
    ];

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);

    function setUp() public {
        string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
        srcForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();

        string memory destRpcUrl = vm.envString("BSC_TESTNET_RPC_URL");
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
        bytes memory initData = abi.encodeCall(eBTC.initialize, address(eBTCManagerInstance));
        ERC1967Proxy proxy = new ERC1967Proxy(address(eBTCImplementation), initData);
        eBTCToken = eBTC(address(proxy));

        vm.makePersistent(address(baseChainCoordinator), address(eBTCManagerInstance), address(eBTCToken));

        vm.startPrank(owner);
        eBTCManagerInstance.setBaseChainCoordinator(address(baseChainCoordinator));
        eBTCManagerInstance.setEBTC(address(eBTCToken));
        vm.stopPrank();

        vm.selectFork(srcForkId);
        lzHelper = new LayerZeroV2Helper();

        // Deploy implementation and proxy for BitcoinLightClient using ERC1967Proxy
        BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
        bytes memory lightClientInitData = abi.encodeCall(
            BitcoinLightClient.initialize,
            (
                owner,
                MINT_BLOCK_VERSION,
                MINT_BLOCK_TIMESTAMP,
                MINT_DIFFICULTY_BITS,
                MINT_NONCE,
                MINT_HEIGHT,
                MINT_PREV_BLOCK,
                MINT_MERKLE_ROOT
            )
        );
        ERC1967Proxy lightClientProxy = new ERC1967Proxy(address(bitcoinLightClientImplementation), lightClientInitData);
        btcLightClient = BitcoinLightClient(address(lightClientProxy));

        vm.prank(owner);
        homeChainCoordinator = new HomeChainCoordinator(
            address(btcLightClient), srcNetworkConfig.endpoint, owner, srcNetworkConfig.chainEid
        );
        vm.makePersistent(address(homeChainCoordinator), address(btcLightClient));

        // Set the receiver first
        bytes32 sender = bytes32(uint256(uint160(address(homeChainCoordinator))));
        bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));

        // Set up peer on destination chain
        vm.selectFork(destForkId);
        vm.prank(owner);
        baseChainCoordinator.setPeer(srcNetworkConfig.chainEid, sender);

        // Set receivers and peers on both chains
        vm.selectFork(srcForkId);
        vm.prank(owner);
        homeChainCoordinator.setPeer(destNetworkConfig.chainEid, receiver);

        // Fund the contract
        // Already on the source chain
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

    function _sendMessage() internal {
        vm.selectFork(srcForkId);

        (uint256 nativeFee,) = homeChainCoordinator.quote(MINT_BTC_TXN_HASH, MINT_RAW_TXN, false);
        bytes32[] memory proof = new bytes32[](10);
        proof[0] = 0x771f9e8396cf0951074953f3db7ae7854093bbec264a2d9c109c4680316785ad;
        proof[1] = 0xd5483c718df6d3417d788cf3d4e769e140e592cf5f6299650e2872d7d59435a6;
        proof[2] = 0xa64f707afd0f6781e74118836a6bfe8c56717a5b3578f20699ea0c73b41ded4b;
        proof[3] = 0x3f81526dba39e72826d9ab3ac055bac9ba5eeeebff9b2a4ca9320eeb585dc2e3;
        proof[4] = 0xba98f7590a316996254454710160411fb61b2ac11079328ad478a030c15e443a;
        proof[5] = 0x0c9b3f0cfe82dd6d453bd91dfdf28e1bebf8fe78f6ffb11b56967410a46844dd;
        proof[6] = 0xf5526c029bef019fccd64d413ea34e33f3ffa7c0b8e8b607a47f1d79763990a8;
        proof[7] = 0x3214d9572fb5b955a1e15de1790323f27b6890127eb3e67044e7d38570cc72c5;
        proof[8] = 0x628e244ab752597ee537cb477cae8ef6e0f2752ac3e58f930be8e26a1561646e;
        proof[9] = 0xb323bd675d1e437ef3059cf2fdda0e085518da250f84a85776ecc6d38503e6ca;
        uint256 index = 242;

        vm.recordLogs();
        vm.startPrank(owner);
        HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams(
            true, // isMint
            MINT_BLOCK_HASH,
            MINT_BTC_TXN_HASH,
            proof,
            index,
            MINT_RAW_TXN,
            TAPROOT_ADDRESS,
            NETWORK_KEY,
            OPERATORS
        );
        homeChainCoordinator.storeMessage(params);
        homeChainCoordinator.sendMessage{value: nativeFee}(MINT_BTC_TXN_HASH);
        vm.stopPrank();

        // Process the message on destination chain
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(destNetworkConfig.endpoint, destForkId, logs);
    }

    function testSendMessage() public {
        // Back to source chain for sending message
        _sendMessage();

        // Get eBTC balance of the designated receiver
        vm.selectFork(destForkId);
        uint256 balance = eBTCToken.balanceOf(BTC_RECEIVER);
        assertEq(balance, BTC_AMOUNT);
    }

    function testBurnFlow() public {
        // Send message first
        _sendMessage();

        ///////////////////////
        // BURN Flow
        //////////////////////
        vm.selectFork(destForkId);
        burnLzHelper = new LayerZeroV2Helper();
        vm.deal(address(BTC_RECEIVER), 10000 ether); // This is 10000 native tokens on the destination chain (BSC Testnet)

        vm.recordLogs();
        vm.startPrank(BTC_RECEIVER);
        eBTCToken.approve(address(baseChainCoordinator), BTC_AMOUNT);
        baseChainCoordinator.burnAndUnlock{value: 1 ether}(BURN_RAW_TXN, BTC_AMOUNT);
        vm.stopPrank();

        bytes32[] memory burnProof = new bytes32[](10);
        burnProof[0] = 0x78e70c28a925ae62e5ca358d0437ce6aad745764829f4018c5897a9b8578a824;
        burnProof[1] = 0x6c49cd9a8d3662880089119f59f7dc1606342deab2e4f3cc7a2d6b9f443d0e07;
        burnProof[2] = 0x3ccda3a19c742f5a4c33aa173ae20748a2685c7f8664fb8508c45fe5fa93622a;
        burnProof[3] = 0x823b46da86b3267b2dfc59d77b0047e1ea22ffd27b086a8a05d6f43d8d852a9a;
        burnProof[4] = 0x5017c554f57188bd237c079b96fcc9526810d58da483acb998f4a2d4175994b7;
        burnProof[5] = 0x1e12a24aed5496fb4c8a4bdc0d3f7dddd20bb291c2d68ad8777ca59fb063e36f;
        burnProof[6] = 0x81e1d89ae8d3d8457fbf800009d4b4740509acab8c6803e2d1b51dbf52057aef;
        burnProof[7] = 0x7a9a5fb6361319c322c326e8e8c419c826b2e3f4d2e60a928ed2e8d06ad0191c;
        burnProof[8] = 0x64da1f3f0cb701eded7a70910bf1e6e8860e66c4ef32019a10281b58427e5bc5;
        burnProof[9] = 0x7dfa9f8f8744c5bd0dd9f239771a059ba57b1e9c0eb4cda336ff719eeb46a729;
        uint256 burnTxnIndex = 19;

        // Process the message on the source chain
        Vm.Log[] memory burnLogs = vm.getRecordedLogs();
        burnLzHelper.help(srcNetworkConfig.endpoint, srcForkId, burnLogs);

        vm.selectFork(srcForkId);

        HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams(
            false, // isMint
            BURN_BLOCK_HASH,
            BURN_BTC_TXN_HASH,
            burnProof,
            burnTxnIndex,
            BURN_RAW_TXN,
            TAPROOT_ADDRESS,
            NETWORK_KEY,
            OPERATORS
        );

        vm.startPrank(owner);
        homeChainCoordinator.submitBlockAndStoreMessage(BURN_BLOCK_HEADER, new bytes[](0), params);
        homeChainCoordinator.updateBurnStatus(BURN_BTC_TXN_HASH);
        vm.stopPrank();

        // Get primary status of the burn and the eBTC balance of the user on the destination chain
        PSBTData memory burnPsbtData = homeChainCoordinator.getPSBTDataForTxnHash(BURN_BTC_TXN_HASH);
        assertEq(burnPsbtData.status, true);

        vm.selectFork(destForkId);
        uint256 balance = eBTCToken.balanceOf(BTC_RECEIVER);
        assertEq(balance, 0);
    }

    function testBurnInvalidPSBT() public {
        // Send message first
        _sendMessage();

        ///////////////////////
        // BURN Flow
        //////////////////////
        vm.selectFork(destForkId);
        burnLzHelper = new LayerZeroV2Helper();
        vm.deal(address(BTC_RECEIVER), 10000 ether);

        // 1. Send message with invalid psbt via the BaseChainCoordinator for the burn txn
        bytes memory invalidBurnPsbt =
            hex"02000000000101fbf9699c877c3d16743092ce0c738b6b1ae5d8b67120c692d2a69da357c95d130000000000ffffffff02a00f000000000000160014cf54150aff704eb4ecae400d9e665eb285dcbfaf900100000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10440957764f9545df6a9965bb462c47a712974aa97fd6ea0fc27ec23bd6d504cf59a6375c0d35fbdd7fcfe07eb7810fb1035d63c9c6e683368e37c341e778926c1ce4012846f5f7501c92da8a3bc37de768c91d27e36a91400761cae180c18f53b6dd6faccea1af3087b7b542b76e5647fe69ceaca1804620d2ffc9cc405619e6759a844206a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb2506ad201a4b83276e5b4ddcf3f7f52615b35c39b013c94f58b941019ddf2be7b511568fac41c16a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb25061c38128ccf96002c3f5ce0e3b9d4d587a7744ba51e4814c2b2569b89cf09640700000000"; // Invalid psbt / Mint psbt
        bytes32 invalidBurnTxnHash = TxidCalculator.calculateTxid(invalidBurnPsbt);

        vm.recordLogs();
        vm.startPrank(BTC_RECEIVER);
        eBTCToken.approve(address(baseChainCoordinator), BTC_AMOUNT);
        baseChainCoordinator.burnAndUnlock{value: 1 ether}(invalidBurnPsbt, BTC_AMOUNT);
        vm.stopPrank();

        uint256 initialBalancePostBurn = eBTCToken.balanceOf(BTC_RECEIVER);
        assertEq(initialBalancePostBurn, 0);

        // 2. Initiate a txn with the invalid psbt on the HomeChainCoordinator to mint back the eBTC
        Vm.Log[] memory burnLogs = vm.getRecordedLogs();
        // Expect this to revert as this is a case of sending invalidBurnPsbt from baseChainCoordinator
        vm.expectRevert(HomeChainCoordinator.InvalidRequest.selector);
        burnLzHelper.help(srcNetworkConfig.endpoint, srcForkId, burnLogs);

        vm.selectFork(srcForkId);
        lzHelper = new LayerZeroV2Helper();

        vm.recordLogs();
        vm.startPrank(BTC_RECEIVER);
        homeChainCoordinator.unlockBurntEBTC{value: 50 ether}(destNetworkConfig.chainEid, invalidBurnTxnHash);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(destNetworkConfig.endpoint, destForkId, logs);

        vm.selectFork(destForkId);
        uint256 finalBalancePostRetry = eBTCToken.balanceOf(BTC_RECEIVER);
        assertEq(finalBalancePostRetry, BTC_AMOUNT);
    }
}
