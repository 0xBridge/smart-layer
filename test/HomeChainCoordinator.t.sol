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
    uint256 private constant BTC_AMOUNT = 10000;

    // Bitcoin Testnet4 constants for Block #80169
    uint32 private constant MINT_BLOCK_VERSION = 624918528; // Hex: 0x253f8000
    uint32 private constant MINT_BLOCK_TIMESTAMP = 1745999896; // Hex: 0x6811d818
    uint32 private constant MINT_DIFFICULTY_BITS = 419821129; // Hex: 0x1905f649
    uint32 private constant MINT_NONCE = 183420755; // Hex: 0xaeec753
    uint32 private constant MINT_BLOCK_HEIGHT = 80169;
    bytes32 private constant MINT_PREV_BLOCK = 0x000000003b4bb24d32b1a5401933e3428188670c18eb8459b147c0575dde8151;
    bytes32 private constant MINT_MERKLE_ROOT = 0x70529ffb76a57e9c3a5b29cc6faf0dc8dba0eb4eef82bd9ee70ac1435ad12b2d;

    bytes MINT_BLOCK_HEADER = hex"00803f255181de5d57c047b15984eb180c67888142e3331940a5b1324db24b3b000000002d2bd15a43c10ae79ebd82ef4eeba0dbc80daf6fcc295b3a9c7ea576fb9f527018d8116849f6051953c7ee0a";
    bytes32 private constant MINT_BLOCK_HASH = 0x0000000000000004d815fad54546ee91bca946a5b96ab989fada5fa2c3041e02;
    bytes32 private constant MINT_BTC_TXN_HASH = 0xc10ef0ce4ac0cbc7ffffabcc2804e70cc1f332fc29e78d79832d6d67c3b80842;
    bytes MINT_RAW_TXN =
        hex"02000000000101e48a9f3270ab1ed56b721df9f6dd24af940d23d9c73a9e9bf5a6ac93b2cf15fc0300000000ffffffff041027000000000000225120b2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33be80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144e56a8e3757f167378b38269e1ca0e1a1f124c9e00080000000000002710000400009ca60008000000000000007b8d49000000000000160014d5a028b62114136a63ebcfacf94e18536b90a12102483045022100e36cb24dad4e568561b7a1d00ede31931b624e9698ce020e518bd1cfb9bd895802204b37fd88086672304c3b754e3df32298adcc0bdeebdbf21d7616de027d1b86b10121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";


    // Bitcoin Testnet4 constants for Block #81081
    uint32 private constant BURN_BLOCK_VERSION = 555778048; // Hex: 0x21208000
    uint32 private constant BURN_BLOCK_TIMESTAMP = 1746474337; // Hex: 0x68191561
    uint32 private constant BURN_DIFFICULTY_BITS = 419766864; // Hex: 0x19052250
    uint32 private constant BURN_NONCE = 547953751; // Hex: 0x20a91c57
    uint32 private constant BURN_BLOCK_HEIGHT = 81081;
    bytes32 private constant BURN_PREV_BLOCK = 0x000000003c79a46a33020d2eaef37ffd93ba5090b071cddcabeec674cc0b41d4;
    bytes32 private constant BURN_MERKLE_ROOT = 0x49851ea65b93a9cacc91b3bf5bb8afcfe3687630921556adcb77aaeb5a83fa4b;

    bytes BURN_BLOCK_HEADER =
        hex"00802021d4410bcc74c6eeabdccd71b09050ba93fd7ff3ae2e0d02336aa4793c000000004bfa835aebaa77cbad561592307668e3cfafb85bbfb391cccaa9935ba61e85496115196850220519571ca920";
    bytes32 private constant BURN_BLOCK_HASH = 0x00000000000000047604a3983c434b801aacfe241d49f496355f3221f915b8dd;
    bytes32 private constant BURN_BTC_TXN_HASH = 0xb33362b4d1860ef43fe71414a6292fae653a50e4d76f2a0f154c1231f6e03b72;
    bytes PARTIALLY_SIGNED_RAW_TXN_BTC = hex"63484E6964503842414A41434141414141554949754D4E6E625332446559336E4B6677793838454D3577516F7A4B762F2F38664C7745724F38413742414141414141442F2F2F2F2F417A516841414141414141414667415574364970734D48424443464E47786E524A6A746E6C39726A3658685341774141414141414142594146484851524B3633394249467165384F505868656654696E64732B68747745414141414141414157414254566F43693249525154616D50727A367A355468685461354368495141414141414141514572454363414141414141414169555343796B6C5A6C3952476B3742554832584547414C346E393548344154454854473761567A6B464E78547A4F304555616B4E594D684C56536C6C33387337305631494D55677135763549706D7931304152374E515176624A5161436673784D6253704653556D6A36537238716A6372612F75514C6368495037454F7034797A686872696B454138414170586666685A44464C5A306C493842377245526B6A6E55533365676F686B5966654D7558494C3264364A7136754C445A522F685A4D3832582F517274587A563349655667676C6D6C394B456B7570426A337A51685842616B4E594D684C56536C6C33387337305631494D55677135763549706D7931304152374E515176624A5159634F424B4D7A3559414C443963344F4F35314E57487033524C70523549464D4B795670754A7A776C6B42305567616B4E594D684C56536C6C33387337305631494D55677135763549706D7931304152374E515176624A5161744942704C6779647557303363382F66314A68577A58446D7745386C50574C6C42415A33664B2B653145566150724D414141414141";
    bytes BURN_RAW_TXN =
        hex"020000000001014208b8c3676d2d83798de729fc32f3c10ce70428ccabffffc7cbc04acef00ec10000000000ffffffff033421000000000000160014b7a229b0c1c10c214d1b19d1263b6797dae3e978520300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa1b701000000000000160014d5a028b62114136a63ebcfacf94e18536b90a1210440dee7bd859e6619e6b68e7fb6715bc3b4d87cbb96105113612de624b5b88e5ca7910f578c2380385c8752fe31b9976b52ef4da7f30257b1443aa59d656d7ad5a8403c000a577df8590c52d9d2523c07bac44648e7512dde82886461f78cb9720bd9de89abab8b0d947f85933cd97fd0aed5f357721e5608259a5f4a124ba9063df344206a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb2506ad201a4b83276e5b4ddcf3f7f52615b35c39b013c94f58b941019ddf2be7b511568fac41c16a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb25061c38128ccf96002c3f5ce0e3b9d4d587a7744ba51e4814c2b2569b89cf09640700000000";

    // AVS Data (Dummy values)
    bytes32 private constant TAPROOT_ADDRESS = 0xb2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33b;
    bytes32 private constant NETWORK_KEY = 0xb7a229b0c1c10c214d1b19d1263b6797dae3e978000000000000000000000000;
    address[] private OPERATORS = [
        0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE,
        0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E,
        0xEC1Fa15145c4d27F7e8645F2F68c0E0303AE5690
    ];

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);

    function setUp() public {
        string memory srcRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
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
                MINT_BLOCK_HEIGHT,
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

        // TODO: Update this based on the MINT_BTC_TXN_HASH
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

        uint256 intialBalance = eBTCToken.balanceOf(BTC_RECEIVER);
        console.log("Initial eBTC balance of the BTC_RECEIVER: ", intialBalance);

        vm.recordLogs();
        vm.startPrank(BTC_RECEIVER);
        eBTCToken.approve(address(baseChainCoordinator), BTC_AMOUNT);
        bytes32 keccakTxnHash = keccak256(PARTIALLY_SIGNED_RAW_TXN_BTC);
        console.logBytes32(keccakTxnHash);
        bytes memory newPayload = abi.encode(BTC_AMOUNT, BTC_RECEIVER, PARTIALLY_SIGNED_RAW_TXN_BTC);
        console.logBytes(newPayload);
        (uint256 burnMessageRelayerFee, ) = baseChainCoordinator.quote(
            srcNetworkConfig.chainEid, newPayload, false
        );
        console.log("Burn message relayer fee: ", burnMessageRelayerFee);
        baseChainCoordinator.burnAndUnlock{value: burnMessageRelayerFee*2}(PARTIALLY_SIGNED_RAW_TXN_BTC, BTC_AMOUNT); // TODO: Check if the fee is correct
        console.log("Burned eBTC amount: ", BTC_AMOUNT);
        vm.stopPrank();

        // bytes32[] memory burnProof = new bytes32[](10);
        // burnProof[0] = 0x78e70c28a925ae62e5ca358d0437ce6aad745764829f4018c5897a9b8578a824;
        // burnProof[1] = 0x6c49cd9a8d3662880089119f59f7dc1606342deab2e4f3cc7a2d6b9f443d0e07;
        // burnProof[2] = 0x3ccda3a19c742f5a4c33aa173ae20748a2685c7f8664fb8508c45fe5fa93622a;
        // burnProof[3] = 0x823b46da86b3267b2dfc59d77b0047e1ea22ffd27b086a8a05d6f43d8d852a9a;
        // burnProof[4] = 0x5017c554f57188bd237c079b96fcc9526810d58da483acb998f4a2d4175994b7;
        // burnProof[5] = 0x1e12a24aed5496fb4c8a4bdc0d3f7dddd20bb291c2d68ad8777ca59fb063e36f;
        // burnProof[6] = 0x81e1d89ae8d3d8457fbf800009d4b4740509acab8c6803e2d1b51dbf52057aef;
        // burnProof[7] = 0x7a9a5fb6361319c322c326e8e8c419c826b2e3f4d2e60a928ed2e8d06ad0191c;
        // burnProof[8] = 0x64da1f3f0cb701eded7a70910bf1e6e8860e66c4ef32019a10281b58427e5bc5;
        // burnProof[9] = 0x7dfa9f8f8744c5bd0dd9f239771a059ba57b1e9c0eb4cda336ff719eeb46a729;
        // uint256 burnTxnIndex = 19;

        // Process the message on the source chain
        Vm.Log[] memory burnLogs = vm.getRecordedLogs();
        burnLzHelper.help(srcNetworkConfig.endpoint, srcForkId, burnLogs);

        vm.selectFork(srcForkId);

        // Get the burn proof and index
        bytes32[] memory burnProof = new bytes32[](0);
        uint256 burnTxnIndex = 0;
        bytes32 burnBlockHash = bytes32(0);
        HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams(
            false, // isMint
            burnBlockHash,
            keccakTxnHash,
            burnProof,
            burnTxnIndex,
            PARTIALLY_SIGNED_RAW_TXN_BTC,
            TAPROOT_ADDRESS,
            NETWORK_KEY,
            OPERATORS
        );



        vm.startPrank(owner);
        // bytes[] memory intermediateHeaders = new bytes[](BURN_BLOCK_HEIGHT - MINT_BLOCK_HEIGHT);
        // homeChainCoordinator.submitBlockAndStoreMessage(BURN_BLOCK_HEADER, intermediateHeaders, params); // TODO: This will create an issue if the block headers are not set
        homeChainCoordinator.updateBurnStatus(keccakTxnHash, BURN_BTC_TXN_HASH);
        vm.stopPrank();

        // Get primary status of the burn and the eBTC balance of the user on the destination chain
        PSBTData memory burnPsbtData = homeChainCoordinator.getPSBTDataForTxnHash(keccakTxnHash);
        assertEq(burnPsbtData.actualTxnHash, BURN_BTC_TXN_HASH);

        vm.selectFork(destForkId);
        uint256 balance = eBTCToken.balanceOf(BTC_RECEIVER);
        assertEq(balance, intialBalance - BTC_AMOUNT);
    }

}
