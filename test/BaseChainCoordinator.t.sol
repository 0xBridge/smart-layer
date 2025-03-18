// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import {Test, Vm} from "forge-std/Test.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {LayerZeroV2Helper} from "lib/pigeon/src/layerzero-v2/LayerZeroV2Helper.sol";
// import {HelperConfig} from "../script/HelperConfig.s.sol";
// import {HomeChainCoordinator, PSBTData} from "../src/HomeChainCoordinator.sol";
// import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
// import {TxnData, IBaseChainCoordinator} from "../src/interfaces/IBaseChainCoordinator.sol";
// import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
// import {eBTCManager} from "../src/eBTCManager.sol";
// import {eBTC} from "../src/eBTC.sol";

// contract BaseChainCoordinatorTest is Test {
//     LayerZeroV2Helper private lzHelper;
//     HomeChainCoordinator private homeChainCoordinator;
//     BaseChainCoordinator private baseChainCoordinator;
//     BitcoinLightClient private btcLightClient;
//     eBTCManager private eBTCManagerInstance;
//     eBTC private eBTCToken;

//     HelperConfig.NetworkConfig private srcNetworkConfig;
//     HelperConfig.NetworkConfig private destNetworkConfig;

//     address private owner;
//     uint256 private srcForkId;
//     uint256 private destForkId;

//     // Bitcoin transaction data for burn
//     bytes private constant BURN_RAW_TXN =
//         hex"02000000000102137d512d277b25677a4a7f522581d4d6e47ee85fd3b9353fdc7d17a05ae2e7bd0000000000ffffffff9e504ef8a97d1c29c8df3db5e79fdc2dc362d2d770c66e234a849b915a449e1d0000000000ffffffff028813000000000000160014cf54150aff704eb4ecae400d9e665eb285dcbfaff40100000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10440e0c768d0f30cb9617d4e89a4887be7515a8be186478b2c6554fc8701e04f0f72bd5882710156aed605365c4f74b4b7f767d7ffc2d9730a3c220208bc892f62c44022d47f4bc506a5d4df5263471db65697ad5b74573cd98f534f7ad2dcd2227deaaf1ace3e6186a3d634ffa9ea657a71d39b4b441e9c8b477c2ab9ddde7542e92c44206a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb2506ad201a4b83276e5b4ddcf3f7f52615b35c39b013c94f58b941019ddf2be7b511568fac41c16a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb25061c38128ccf96002c3f5ce0e3b9d4d587a7744ba51e4814c2b2569b89cf09640704408efafc4f08a1c4780daac0990190485025ce8f8443f5297fbdcd3f45e5f0d1fb4817b104e961b42a56ed71a2b43616aa0a62298e5a2a248e713b079f31b88a1d40018bb141f298e78962c25930c554c778978782e5e2627d602131ba99a3c27458b7f51d8c67b22fdc02fac7f3467c7fa5fcd1741041a1b5645a497c92a905b06e44206a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb2506ad201a4b83276e5b4ddcf3f7f52615b35c39b013c94f58b941019ddf2be7b511568fac41c16a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb25061c38128ccf96002c3f5ce0e3b9d4d587a7744ba51e4814c2b2569b89cf09640700000000";
//     bytes32 private constant BURN_BTC_TXN_HASH = 0xfe38ee746989f4372ed260bbc8bfc41ebb7108d714789574aba2057ce8c7bde0;
//     uint256 private constant BTC_AMOUNT = 1357;
//     address private constant BTC_RECEIVER = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;

//     // Bitcoin SPV Testnet constants for burn verification
//     bytes private constant BURN_BLOCK_HEADER =
//         hex"00e0d02560e29304b1f8c6a8c275a9a1c7acf8b6f4b6e2162e8ab18445131686000000000e4ceb7dce5db7e017aad81223fdd2975158e229bd9b4c538703acd701b551a680eaca67c861041926a5421f";
//     bytes32 private constant BURN_BLOCK_HASH = 0x00000000000000022ada2600b6c909cb30c02520a66b55387159a20f1bb924d6;

//     // Events
//     event MessageSent(uint32 dstEid, bytes message, bytes32 receiver, uint256 nativeFee);
//     event Burn(address indexed BTC_RECEIVER, uint256 amount);

//     function setUp() public {
//         // Get network configurations
//         string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
//         srcForkId = vm.createSelectFork(srcRpcUrl);

//         HelperConfig srcConfig = new HelperConfig();
//         srcNetworkConfig = srcConfig.getConfig();

//         string memory destRpcUrl = vm.envString("BSC_TESTNET_RPC_URL");
//         destForkId = vm.createSelectFork(destRpcUrl);

//         HelperConfig destConfig = new HelperConfig();
//         destNetworkConfig = destConfig.getConfig();
//         owner = destNetworkConfig.account;

//         vm.deal(BTC_RECEIVER, 10 ether);

//         // Deploy the contracts on destination chain (BSC Testnet)
//         vm.selectFork(destForkId);
//         vm.startPrank(owner);

//         // Deploy eBTCManager
//         eBTCManagerInstance = new eBTCManager(owner);

//         // Deploy BaseChainCoordinator
//         baseChainCoordinator = new BaseChainCoordinator(
//             destNetworkConfig.endpoint,
//             owner,
//             address(eBTCManagerInstance),
//             destNetworkConfig.chainEid,
//             srcNetworkConfig.chainEid
//         );

//         // Deploy eBTC token
//         eBTC eBTCImplementation = new eBTC();
//         bytes memory initData = abi.encodeWithSelector(eBTC.initialize.selector, address(eBTCManagerInstance));
//         ERC1967Proxy proxy = new ERC1967Proxy(address(eBTCImplementation), initData);
//         eBTCToken = eBTC(address(proxy));

//         // Configure contracts
//         eBTCManagerInstance.setBaseChainCoordinator(address(baseChainCoordinator));
//         eBTCManagerInstance.setEBTC(address(eBTCToken));

//         // Mint tokens for test BTC_RECEIVER
//         deal(address(eBTCToken), BTC_RECEIVER, BTC_AMOUNT * 2, true);

//         vm.stopPrank();

//         // Make contracts persistent
//         lzHelper = new LayerZeroV2Helper();
//         // vm.makePersistent(address(lzHelper));
//         vm.makePersistent(address(baseChainCoordinator), address(eBTCManagerInstance), address(eBTCToken));

//         // Deploy contracts on source chain (Amoy)
//         vm.selectFork(srcForkId);

//         // Set up BitcoinLightClient for HomeChainCoordinator
//         BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
//         bytes memory lightClientInitData = abi.encodeWithSelector(
//             BitcoinLightClient.initialize.selector,
//             owner,
//             536870912, // Block version
//             1741357556, // Block timestamp
//             486604799, // Difficulty bits
//             3368467969, // Nonce
//             1, // Height
//             bytes32(0), // Prev block
//             bytes32(0) // Merkle root
//         );
//         ERC1967Proxy lightClientProxy = new ERC1967Proxy(address(bitcoinLightClientImplementation), lightClientInitData);
//         btcLightClient = BitcoinLightClient(address(lightClientProxy));

//         vm.prank(owner);
//         homeChainCoordinator = new HomeChainCoordinator(
//             address(btcLightClient), srcNetworkConfig.endpoint, owner, srcNetworkConfig.chainEid
//         );

//         vm.makePersistent(address(homeChainCoordinator), address(btcLightClient));

//         // Set up peer relationships
//         bytes32 homeChainSender = bytes32(uint256(uint160(address(homeChainCoordinator))));
//         bytes32 baseChainReceiver = bytes32(uint256(uint160(address(baseChainCoordinator))));

//         // Set peers on source chain
//         vm.prank(owner);
//         homeChainCoordinator.setPeer(destNetworkConfig.chainEid, baseChainReceiver);

//         // Set peers on destination chain
//         vm.selectFork(destForkId);
//         vm.prank(owner);
//         baseChainCoordinator.setPeer(srcNetworkConfig.chainEid, homeChainSender);
//     }

//     function testBurnAndUnlock() public {
//         vm.selectFork(destForkId);

//         // Check initial balances
//         uint256 initialBalance = eBTCToken.balanceOf(BTC_RECEIVER);
//         assertEq(initialBalance, BTC_AMOUNT * 2, "Initial balance should be double the BTC amount");

//         // Approve tokens
//         vm.startPrank(BTC_RECEIVER);
//         eBTCToken.approve(address(baseChainCoordinator), BTC_AMOUNT);

//         // Record logs for events and cross-chain messaging
//         vm.recordLogs();

//         // Execute burnAndUnlock
//         baseChainCoordinator.burnAndUnlock{value: 1 ether}(BURN_RAW_TXN, BTC_AMOUNT);
//         vm.stopPrank();

//         // Check final balances
//         uint256 finalBalance = eBTCToken.balanceOf(BTC_RECEIVER);
//         assertEq(finalBalance, BTC_AMOUNT, "Final balance should be reduced by BTC amount");

//         // Verify transaction data in BaseChainCoordinator
//         TxnData memory txnData = baseChainCoordinator.getTxnData(BURN_BTC_TXN_HASH);
//         assertTrue(txnData.status, "Transaction should be marked as processed");
//         assertEq(txnData.user, BTC_RECEIVER, "Transaction BTC_RECEIVER should match");
//         assertEq(txnData.amount, BTC_AMOUNT, "Transaction amount should match");

//         // Verify events
//         Vm.Log[] memory logs = vm.getRecordedLogs();
//         bool burnEventFound = false;
//         bool messageSentEventFound = false;

//         for (uint256 i = 0; i < logs.length; i++) {
//             // Check for MessageSent event
//             if (logs[i].topics[0] == keccak256("MessageSent(uint32,bytes,bytes32,uint256)")) {
//                 messageSentEventFound = true;
//             }
//         }

//         assertTrue(burnEventFound, "Burn event should be emitted");
//         assertTrue(messageSentEventFound, "MessageSent event should be emitted");

//         // Process the cross-chain message on source chain (Amoy)
//         lzHelper.help(srcNetworkConfig.endpoint, srcForkId, logs);

//         // Verify the message was received on source chain
//         vm.selectFork(srcForkId);

//         // Get the data from HomeChainCoordinator
//         PSBTData memory psbtData = homeChainCoordinator.getPSBTDataForTxnHash(BURN_BTC_TXN_HASH);

//         // Verify the recorded data
//         assertEq(psbtData.txnType, false, "Transaction type should be burn (false)");
//         assertEq(psbtData.rawTxn, BURN_RAW_TXN, "Raw transaction should match");

//         // Completing the flow by verifying and updating burn status
//         bytes32[] memory burnProof = new bytes32[](10);
//         burnProof[0] = 0x78e70c28a925ae62e5ca358d0437ce6aad745764829f4018c5897a9b8578a824;
//         burnProof[1] = 0x6c49cd9a8d3662880089119f59f7dc1606342deab2e4f3cc7a2d6b9f443d0e07;
//         burnProof[2] = 0x3ccda3a19c742f5a4c33aa173ae20748a2685c7f8664fb8508c45fe5fa93622a;
//         burnProof[3] = 0x823b46da86b3267b2dfc59d77b0047e1ea22ffd27b086a8a05d6f43d8d852a9a;
//         burnProof[4] = 0x5017c554f57188bd237c079b96fcc9526810d58da483acb998f4a2d4175994b7;
//         burnProof[5] = 0x1e12a24aed5496fb4c8a4bdc0d3f7dddd20bb291c2d68ad8777ca59fb063e36f;
//         burnProof[6] = 0x81e1d89ae8d3d8457fbf800009d4b4740509acab8c6803e2d1b51dbf52057aef;
//         burnProof[7] = 0x7a9a5fb6361319c322c326e8e8c419c826b2e3f4d2e60a928ed2e8d06ad0191c;
//         burnProof[8] = 0x64da1f3f0cb701eded7a70910bf1e6e8860e66c4ef32019a10281b58427e5bc5;
//         burnProof[9] = 0x7dfa9f8f8744c5bd0dd9f239771a059ba57b1e9c0eb4cda336ff719eeb46a729;

//         uint256 burnTxnIndex = 19;

//         // Complete burn verification with a block submission and status update
//         vm.startPrank(owner);

//         // Create parameters for storing the message
//         HomeChainCoordinator.StoreMessageParams memory params = HomeChainCoordinator.StoreMessageParams({
//             txnType: false, // This is a burn transaction
//             blockHash: BURN_BLOCK_HASH,
//             btcTxnHash: BURN_BTC_TXN_HASH,
//             proof: burnProof,
//             index: burnTxnIndex,
//             rawTxn: BURN_RAW_TXN,
//             taprootAddress: 0xb2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33b,
//             networkKey: 0xb7a229b0c1c10c214d1b19d1263b6797dae3e978000000000000000000000000,
//             operators: new address[](0)
//         });

//         homeChainCoordinator.submitBlockAndStoreMessage(BURN_BLOCK_HEADER, new bytes[](0), params);
//         homeChainCoordinator.updateBurnStatus(BURN_BTC_TXN_HASH);
//         vm.stopPrank();

//         // Verify burn status was updated
//         psbtData = homeChainCoordinator.getPSBTDataForTxnHash(BURN_BTC_TXN_HASH);
//         assertTrue(psbtData.status, "Burn status should be updated to true");
//     }

//     function testBurnAndUnlockWithInsufficientAmount() public {
//         vm.selectFork(destForkId);

//         // Get minimum required BTC amount
//         uint256 minBtcAmount = eBTCManagerInstance.minBTCAmount();
//         uint256 invalidAmount = minBtcAmount - 1;

//         // Mint small amount to BTC_RECEIVER
//         vm.prank(owner);
//         eBTCToken.mint(BTC_RECEIVER, invalidAmount);

//         // Approve tokens
//         vm.startPrank(BTC_RECEIVER);
//         eBTCToken.approve(address(baseChainCoordinator), invalidAmount);

//         // Expect revert due to insufficient amount
//         vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidAmount(uint256)")), invalidAmount));
//         baseChainCoordinator.burnAndUnlock{value: 1 ether}(BURN_RAW_TXN, invalidAmount);
//         vm.stopPrank();
//     }

//     function testBurnAndUnlockWithInvalidTokenAddress() public {
//         vm.selectFork(destForkId);

//         // Set invalid token address
//         vm.prank(owner);
//         eBTCManagerInstance.setEBTC(address(0));

//         // Expect revert due to invalid token address
//         vm.expectRevert(bytes4(keccak256("InvalidTokenAddress()")));
//         vm.prank(BTC_RECEIVER);
//         baseChainCoordinator.burnAndUnlock{value: 1 ether}(BURN_RAW_TXN, BTC_AMOUNT);
//     }

//     function testMultipleBurnsAndUnlocks() public {
//         vm.selectFork(destForkId);

//         // First burn
//         vm.startPrank(BTC_RECEIVER);
//         eBTCToken.approve(address(baseChainCoordinator), BTC_AMOUNT);
//         baseChainCoordinator.burnAndUnlock{value: 1 ether}(BURN_RAW_TXN, BTC_AMOUNT);
//         vm.stopPrank();

//         // Verify first burn
//         TxnData memory txnData = baseChainCoordinator.getTxnData(BURN_BTC_TXN_HASH);
//         assertTrue(txnData.status, "First transaction should be marked as processed");

//         // Create another user for second burn with different PSBT
//         address user2 = address(0x5678);
//         vm.deal(user2, 10 ether);
//         vm.prank(owner);
//         eBTCToken.mint(user2, BTC_AMOUNT);

//         // Different txn hash for second burn (incrementing last byte)
//         bytes memory secondBurnRawTxn = BURN_RAW_TXN;
//         bytes32 secondBurnTxnHash = bytes32(uint256(BURN_BTC_TXN_HASH) + 1);

//         // Second burn
//         vm.startPrank(user2);
//         eBTCToken.approve(address(baseChainCoordinator), BTC_AMOUNT);
//         baseChainCoordinator.burnAndUnlock{value: 1 ether}(secondBurnRawTxn, BTC_AMOUNT);
//         vm.stopPrank();

//         // Verify second burn
//         TxnData memory txnData2 = baseChainCoordinator.getTxnData(secondBurnTxnHash);
//         assertTrue(txnData2.status, "Second transaction should be marked as processed");
//         assertEq(txnData2.user, user2, "Second transaction BTC_RECEIVER should match");
//     }
// }
