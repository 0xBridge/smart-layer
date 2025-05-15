// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import {Test, Vm, console} from "forge-std/Test.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {LayerZeroV2Helper, Origin} from "lib/pigeon/src/layerzero-v2/LayerZeroV2Helper.sol";
// import {HelperConfig} from "../script/HelperConfig.s.sol";
// import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
// import {eBTCManager} from "../src/eBTCManager.sol";
// import {eBTC} from "../src/eBTC.sol";
// import {IBaseChainCoordinator, TxnData} from "../src/interfaces/IBaseChainCoordinator.sol";

// contract BaseChainCoordinatorTest is Test {
//     // LayerZero Helper
//     LayerZeroV2Helper internal lzHelper;

//     // Contracts
//     BaseChainCoordinator internal baseChainCoordinator;
//     eBTCManager internal eBTCManagerInstance;
//     eBTC internal eBTCToken;

//     // Mocks or addresses for dependencies
//     address internal mockLzEndpoint;
//     address internal homeChainCoordinatorPeer;

//     // Network Config
//     HelperConfig.NetworkConfig internal baseNetworkConfig;
//     uint32 internal constant HOME_CHAIN_EID = 40217; // Example EID for HomeChain (e.g., Holesky)
//     uint32 internal constant BASE_CHAIN_EID = 40161; // Example EID for BaseChain (e.g., Sepolia)

//     // Test accounts
//     address internal owner;
//     address internal user;
//     address internal anotherAddress;

//     // Fork IDs
//     uint256 internal baseForkId;

//     // Constants for testing
//     bytes32 internal constant SAMPLE_BTC_TXN_HASH_MINT = keccak256(abi.encodePacked("sample_btc_txn_hash_mint"));
//     bytes32 internal constant SAMPLE_BTC_TXN_HASH_BURN = keccak256(abi.encodePacked("sample_btc_txn_hash_burn"));
//     bytes32 internal constant ACTUAL_BURN_TXN_HASH = keccak256(abi.encodePacked("actual_burn_txn_hash"));
//     uint256 internal constant MINT_AMOUNT = 1 ether;
//     uint256 internal constant BURN_AMOUNT = 0.5 ether;

//     function setUp() public {
//         owner = makeAddr("owner");
//         user = makeAddr("user");
//         anotherAddress = makeAddr("anotherAddress");
//         homeChainCoordinatorPeer = makeAddr("homeChainCoordinatorPeer");

//         lzHelper = new LayerZeroV2Helper();
//         (mockLzEndpoint,,) = lzHelper.createEndpoint(BASE_CHAIN_EID);

//         string memory baseRpcUrl = vm.envString("SEPOLIA_RPC_URL");
//         if (bytes(baseRpcUrl).length == 0) {
//             baseRpcUrl = "http://localhost:8545";
//         }
//         baseForkId = vm.createSelectFork(baseRpcUrl);

//         baseNetworkConfig = HelperConfig.NetworkConfig({
//             name: "BaseChainTest",
//             chainEid: BASE_CHAIN_EID,
//             endpoint: mockLzEndpoint,
//             confirmations: 3,
//             lzComposeGas: 100000,
//             oAppVersion: 0,
//             blockExplorer: "",
//             relayer: address(0) // Added relayer field
//         });

//         vm.startPrank(owner);

//         eBTCManagerInstance = new eBTCManager(owner);

//         eBTC eBTCImplementation = new eBTC();
//         bytes memory initData = abi.encodeCall(eBTC.initialize, address(eBTCManagerInstance));
//         ERC1967Proxy proxy = new ERC1967Proxy(address(eBTCImplementation), initData);
//         eBTCToken = eBTC(address(proxy));

//         eBTCManagerInstance.setEBTC(address(eBTCToken));

//         baseChainCoordinator = new BaseChainCoordinator(
//             baseNetworkConfig.endpoint,
//             owner,
//             address(eBTCManagerInstance),
//             baseNetworkConfig.chainEid,
//             HOME_CHAIN_EID
//         );

//         eBTCManagerInstance.setBaseChainCoordinator(address(baseChainCoordinator));

//         bytes32 peerBytes32 = bytes32(uint256(uint160(homeChainCoordinatorPeer)));
//         baseChainCoordinator.setPeer(HOME_CHAIN_EID, peerBytes32);

//         vm.stopPrank();

//         vm.deal(owner, 100 ether);
//         vm.deal(user, 10 ether);
//         vm.deal(address(baseChainCoordinator), 10 ether);
//     }

//     function testInitialState() public {
//         assertEq(baseChainCoordinator.owner(), owner);
//         assertEq(address(baseChainCoordinator.eBTCManager()), address(eBTCManagerInstance));
//         assertEq(baseChainCoordinator.lzEndpoint(), baseNetworkConfig.endpoint);
//         assertEq(baseChainCoordinator.eid(), baseNetworkConfig.chainEid);
//         assertEq(baseChainCoordinator.homeChainEid(), HOME_CHAIN_EID);
//         bytes32 expectedPeer = bytes32(uint256(uint160(homeChainCoordinatorPeer)));
//         assertEq(baseChainCoordinator.peers(HOME_CHAIN_EID), expectedPeer);
//     }

//     function testSetPeer() public {
//         address newPeerAddress = makeAddr("newPeer");
//         bytes32 newPeerBytes32 = bytes32(uint256(uint160(newPeerAddress)));
//         uint32 otherChainEid = 12345;

//         vm.expectEmit(true, false, false, true, address(baseChainCoordinator));
//         emit IBaseChainCoordinator.PeerUpdated(otherChainEid, newPeerBytes32);

//         vm.prank(owner);
//         baseChainCoordinator.setPeer(otherChainEid, newPeerBytes32);

//         assertEq(baseChainCoordinator.peers(otherChainEid), newPeerBytes32);
//     }

//     function testSetEBTCManager() public {
//         vm.prank(owner);
//         eBTCManager newEBTCManager = new eBTCManager(owner);

//         vm.expectEmit(true, false, false, true, address(baseChainCoordinator));
//         emit IBaseChainCoordinator.EBTCManagerUpdated(address(newEBTCManager));

//         baseChainCoordinator.setEBTCManager(address(newEBTCManager));
//         assertEq(address(baseChainCoordinator.eBTCManager()), address(newEBTCManager));
//     }

//     function testPauseAndUnpause() public {
//         assertFalse(baseChainCoordinator.paused());
//         vm.prank(owner);
//         baseChainCoordinator.pause();
//         assertTrue(baseChainCoordinator.paused());
//         vm.prank(owner);
//         baseChainCoordinator.unpause();
//         assertFalse(baseChainCoordinator.paused());
//     }

//     function testLzReceive_MintSuccess() public {
//         IBaseChainCoordinator.LzReceiveData memory mintData = IBaseChainCoordinator.LzReceiveData({
//             isMint: true,
//             userAddress: user,
//             btcTxnHash: SAMPLE_BTC_TXN_HASH_MINT,
//             amount: MINT_AMOUNT,
//             isSuccess: true,
//             actualTxnHash: bytes32(0)
//         });
//         bytes memory payload = abi.encode(mintData);

//         Origin memory origin = Origin({
//             srcEid: HOME_CHAIN_EID,
//             sender: bytes32(uint256(uint160(homeChainCoordinatorPeer))),
//             nonce: 1
//         });

//         assertEq(eBTCToken.balanceOf(user), 0);

//         vm.expectEmit(true, true, true, true, address(eBTCManagerInstance));
//         emit eBTCManager.Mint(user, MINT_AMOUNT, SAMPLE_BTC_TXN_HASH_MINT);

//         vm.expectEmit(true, true, true, true, address(baseChainCoordinator));
//         emit IBaseChainCoordinator.MintMessageReceived(user, SAMPLE_BTC_TXN_HASH_MINT, MINT_AMOUNT);

//         vm.prank(mockLzEndpoint);
//         baseChainCoordinator.lzReceive(origin, bytes32(0), payload, address(this));

//         assertEq(eBTCToken.balanceOf(user), MINT_AMOUNT);

//         TxnData memory txnData = baseChainCoordinator.getBtcTxnHashData(SAMPLE_BTC_TXN_HASH_MINT);
//         assertTrue(txnData.processed);
//         assertEq(txnData.userAddress, user);
//         assertEq(txnData.amount, MINT_AMOUNT);
//         assertTrue(txnData.isMint);
//     }

//     function testLzReceive_Mint_WhenPaused_ShouldRevert() public {
//         vm.prank(owner);
//         baseChainCoordinator.pause();

//         IBaseChainCoordinator.LzReceiveData memory mintData = IBaseChainCoordinator.LzReceiveData({
//             isMint: true, userAddress: user, btcTxnHash: SAMPLE_BTC_TXN_HASH_MINT,
//             amount: MINT_AMOUNT, isSuccess: true, actualTxnHash: bytes32(0)
//         });
//         bytes memory payload = abi.encode(mintData);
//         Origin memory origin = Origin({
//             srcEid: HOME_CHAIN_EID, sender: bytes32(uint256(uint160(homeChainCoordinatorPeer))), nonce: 1
//         });

//         vm.prank(mockLzEndpoint);
//         vm.expectRevert("Pausable: paused");
//         baseChainCoordinator.lzReceive(origin, bytes32(0), payload, address(this));
//     }

//     function testLzReceive_Mint_FromUnauthorizedPeer_ShouldRevert() public {
//         address unauthorizedPeer = makeAddr("unauthorizedPeer");
//         IBaseChainCoordinator.LzReceiveData memory mintData = IBaseChainCoordinator.LzReceiveData({
//             isMint: true, userAddress: user, btcTxnHash: SAMPLE_BTC_TXN_HASH_MINT,
//             amount: MINT_AMOUNT, isSuccess: true, actualTxnHash: bytes32(0)
//         });
//         bytes memory payload = abi.encode(mintData);
//         Origin memory origin = Origin({
//             srcEid: HOME_CHAIN_EID, sender: bytes32(uint256(uint160(unauthorizedPeer))), nonce: 1
//         });

//         vm.prank(mockLzEndpoint);
//         vm.expectRevert("OApp: invalid peer");
//         baseChainCoordinator.lzReceive(origin, bytes32(0), payload, address(this));
//     }

//      function testLzReceive_Mint_TxnAlreadyProcessed_ShouldRevert() public {
//         IBaseChainCoordinator.LzReceiveData memory mintData = IBaseChainCoordinator.LzReceiveData({
//             isMint: true, userAddress: user, btcTxnHash: SAMPLE_BTC_TXN_HASH_MINT,
//             amount: MINT_AMOUNT, isSuccess: true, actualTxnHash: bytes32(0)
//         });
//         bytes memory payload = abi.encode(mintData);
//         Origin memory origin1 = Origin({
//             srcEid: HOME_CHAIN_EID, sender: bytes32(uint256(uint160(homeChainCoordinatorPeer))), nonce: 1
//         });
//         vm.prank(mockLzEndpoint);
//         baseChainCoordinator.lzReceive(origin1, bytes32(0), payload, address(this));

//         Origin memory origin2 = Origin({ // New LZ message, new nonce
//             srcEid: HOME_CHAIN_EID, sender: bytes32(uint256(uint160(homeChainCoordinatorPeer))), nonce: 2
//         });
//         vm.prank(mockLzEndpoint);
//         vm.expectRevert(IBaseChainCoordinator.TxnAlreadyProcessed.selector);
//         baseChainCoordinator.lzReceive(origin2, bytes32(0), payload, address(this));
//     }

//     function testLzReceive_BurnConfirmation_Success() public {
//         vm.prank(owner);
//         eBTCManagerInstance.mint(user, BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_MINT);
//         vm.stopPrank();

//         vm.startPrank(user);
//         eBTCToken.approve(address(eBTCManagerInstance), BURN_AMOUNT);
//         vm.expectEmit(true, true, true, true, address(eBTCManagerInstance)); // For BurnInitiated
//         emit eBTCManager.BurnInitiated(user, BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_BURN);
//         // Note: eBTCManager.burn also calls BaseChainCoordinator.initiateBurn, which sends an LZ message.
//         // We are not testing that sending part here, only the lzReceive for burn status.
//         eBTCManagerInstance.burn(BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_BURN);
//         vm.stopPrank();

//         assertEq(eBTCToken.balanceOf(user), 0);
//         assertEq(eBTCToken.balanceOf(address(eBTCManagerInstance)), BURN_AMOUNT);

//         IBaseChainCoordinator.LzReceiveData memory burnConfirmData = IBaseChainCoordinator.LzReceiveData({
//             isMint: false, userAddress: user, btcTxnHash: SAMPLE_BTC_TXN_HASH_BURN,
//             amount: BURN_AMOUNT, isSuccess: true, actualTxnHash: ACTUAL_BURN_TXN_HASH
//         });
//         bytes memory payload = abi.encode(burnConfirmData);
//         Origin memory origin = Origin({
//             srcEid: HOME_CHAIN_EID, sender: bytes32(uint256(uint160(homeChainCoordinatorPeer))), nonce: 2
//         });

//         vm.expectEmit(true, true, true, true, address(eBTCManagerInstance));
//         emit eBTCManager.BurnCompleted(user, BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_BURN, ACTUAL_BURN_TXN_HASH);

//         vm.expectEmit(true, true, true, true, address(baseChainCoordinator));
//         emit IBaseChainCoordinator.BurnStatusMessageReceived(user, SAMPLE_BTC_TXN_HASH_BURN, BURN_AMOUNT, true, ACTUAL_BURN_TXN_HASH);

//         vm.prank(mockLzEndpoint);
//         baseChainCoordinator.lzReceive(origin, bytes32(0), payload, address(this));

//         assertEq(eBTCToken.balanceOf(address(eBTCManagerInstance)), 0);

//         TxnData memory txnData = baseChainCoordinator.getBtcTxnHashData(SAMPLE_BTC_TXN_HASH_BURN);
//         assertTrue(txnData.processed);
//         assertEq(txnData.userAddress, user);
//         assertEq(txnData.amount, BURN_AMOUNT);
//         assertFalse(txnData.isMint);
//         assertTrue(txnData.isSuccess);
//         assertEq(txnData.actualTxnHash, ACTUAL_BURN_TXN_HASH);
//     }

//     function testLzReceive_BurnConfirmation_Failure() public {
//         vm.prank(owner);
//         eBTCManagerInstance.mint(user, BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_MINT);
//         vm.stopPrank();

//         vm.startPrank(user);
//         eBTCToken.approve(address(eBTCManagerInstance), BURN_AMOUNT);
//         eBTCManagerInstance.burn(BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_BURN);
//         vm.stopPrank();

//         assertEq(eBTCToken.balanceOf(user), 0);
//         assertEq(eBTCToken.balanceOf(address(eBTCManagerInstance)), BURN_AMOUNT);

//         IBaseChainCoordinator.LzReceiveData memory burnFailData = IBaseChainCoordinator.LzReceiveData({
//             isMint: false, userAddress: user, btcTxnHash: SAMPLE_BTC_TXN_HASH_BURN,
//             amount: BURN_AMOUNT, isSuccess: false, actualTxnHash: bytes32(0)
//         });
//         bytes memory payload = abi.encode(burnFailData);
//         Origin memory origin = Origin({
//             srcEid: HOME_CHAIN_EID, sender: bytes32(uint256(uint160(homeChainCoordinatorPeer))), nonce: 3
//         });

//         vm.expectEmit(true, true, true, true, address(eBTCManagerInstance));
//         emit eBTCManager.BurnReverted(user, BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_BURN);

//         vm.expectEmit(true, true, true, true, address(baseChainCoordinator));
//         emit IBaseChainCoordinator.BurnStatusMessageReceived(user, SAMPLE_BTC_TXN_HASH_BURN, BURN_AMOUNT, false, bytes32(0));

//         vm.prank(mockLzEndpoint);
//         baseChainCoordinator.lzReceive(origin, bytes32(0), payload, address(this));

//         assertEq(eBTCToken.balanceOf(user), BURN_AMOUNT);
//         assertEq(eBTCToken.balanceOf(address(eBTCManagerInstance)), 0);

//         TxnData memory txnData = baseChainCoordinator.getBtcTxnHashData(SAMPLE_BTC_TXN_HASH_BURN);
//         assertTrue(txnData.processed);
//         assertFalse(txnData.isSuccess);
//     }

//     function testLzReceive_Burn_TxnAlreadyProcessed_ShouldRevert() public {
//         vm.prank(owner);
//         eBTCManagerInstance.mint(user, BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_MINT);
//         vm.stopPrank();
//         vm.startPrank(user);
//         eBTCToken.approve(address(eBTCManagerInstance), BURN_AMOUNT);
//         eBTCManagerInstance.burn(BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_BURN);
//         vm.stopPrank();

//         IBaseChainCoordinator.LzReceiveData memory burnConfirmData = IBaseChainCoordinator.LzReceiveData({
//             isMint: false, userAddress: user, btcTxnHash: SAMPLE_BTC_TXN_HASH_BURN,
//             amount: BURN_AMOUNT, isSuccess: true, actualTxnHash: ACTUAL_BURN_TXN_HASH
//         });
//         bytes memory payload = abi.encode(burnConfirmData);
//         Origin memory origin1 = Origin({
//             srcEid: HOME_CHAIN_EID, sender: bytes32(uint256(uint160(homeChainCoordinatorPeer))), nonce: 1
//         });
//         vm.prank(mockLzEndpoint);
//         baseChainCoordinator.lzReceive(origin1, bytes32(0), payload, address(this));

//         Origin memory origin2 = Origin({
//             srcEid: HOME_CHAIN_EID, sender: bytes32(uint256(uint160(homeChainCoordinatorPeer))), nonce: 2
//         });
//         vm.prank(mockLzEndpoint);
//         vm.expectRevert(IBaseChainCoordinator.TxnAlreadyProcessed.selector);
//         baseChainCoordinator.lzReceive(origin2, bytes32(0), payload, address(this));
//     }

//     function testLzReceive_Burn_InvalidAmount_ShouldRevert() public {
//         vm.prank(owner);
//         eBTCManagerInstance.mint(user, BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_MINT);
//         vm.stopPrank();
//         vm.startPrank(user);
//         eBTCToken.approve(address(eBTCManagerInstance), BURN_AMOUNT);
//         eBTCManagerInstance.burn(BURN_AMOUNT, SAMPLE_BTC_TXN_HASH_BURN);
//         vm.stopPrank();

//         IBaseChainCoordinator.LzReceiveData memory burnConfirmData = IBaseChainCoordinator.LzReceiveData({
//             isMint: false, userAddress: user, btcTxnHash: SAMPLE_BTC_TXN_HASH_BURN,
//             amount: BURN_AMOUNT + 1, isSuccess: true, actualTxnHash: ACTUAL_BURN_TXN_HASH
//         });
//         bytes memory payload = abi.encode(burnConfirmData);
//         Origin memory origin = Origin({
//             srcEid: HOME_CHAIN_EID, sender: bytes32(uint256(uint160(homeChainCoordinatorPeer))), nonce: 1
//         });

//         vm.prank(mockLzEndpoint);
//         vm.expectRevert("eBTCManager: Amount mismatch");
//         baseChainCoordinator.lzReceive(origin, bytes32(0), payload, address(this));
//     }

//     function testWithdrawToken() public {
//         eBTC dummyToken = new eBTC(); // Using eBTC as a generic ERC20
//         vm.prank(owner);
//         dummyToken.initialize(owner); // Dummy initialization
//         vm.prank(owner); // Owner of dummyToken mints
//         dummyToken.mint(address(baseChainCoordinator), 1000);

//         assertEq(dummyToken.balanceOf(address(baseChainCoordinator)), 1000);
//         assertEq(dummyToken.balanceOf(owner), 0);

//         vm.prank(owner); // Owner of BaseChainCoordinator withdraws
//         baseChainCoordinator.withdrawToken(address(dummyToken), owner, 1000);

//         assertEq(dummyToken.balanceOf(address(baseChainCoordinator)), 0);
//         assertEq(dummyToken.balanceOf(owner), 1000);
//     }

//     function testWithdrawToken_NotOwner_ShouldRevert() public {
//         eBTC dummyToken = new eBTC();
//         vm.prank(owner);
//         dummyToken.initialize(owner);
//         vm.prank(owner);
//         dummyToken.mint(address(baseChainCoordinator), 1000);

//         vm.prank(anotherAddress);
//         vm.expectRevert("Ownable: caller is not the owner");
//         baseChainCoordinator.withdrawToken(address(dummyToken), anotherAddress, 1000);
//     }
// }
