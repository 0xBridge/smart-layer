// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.28;

// import {Test, console2, Vm} from "forge-std/Test.sol";
// import {HomeChainCoordinator} from "../../src/experimental/HomeChainCoordinator.sol";
// import {BaseChainCoordinator} from "../../src/experimental/BaseChainCoordinator.sol";
// import {HelperConfig} from "../../script/experimental/HelperConfig.s.sol";
// import {IOAppCore} from "lib/devtools/packages/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
// import {LayerZeroV2Helper} from "lib/pigeon/src/layerzero-v2/LayerZeroV2Helper.sol";
// // import {OptionsBuilder} from "lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// contract CoordinatorHomeChainTest is Test {
//     // using OptionsBuilder for bytes;

//     LayerZeroV2Helper private lzHelper;
//     HomeChainCoordinator private homeChainCoordinator;
//     BaseChainCoordinator private baseChainCoordinator;
//     HelperConfig private homeConfig;
//     HelperConfig private baseConfig;
//     address private usdc;

//     address private owner;
//     address private user;
//     // address private receiver;
//     uint256 private constant INITIAL_BALANCE = 100_000e6; // 1000_000 USDC
//     uint256 private constant AMOUNT_TO_BRIDGE = 4000e6; // 4000 USDC
//     uint32 private constant OP_EID = 30111;
//     address private constant OPTIMISM_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;

//     uint256 private sourceForkId;
//     uint256 private destForkId;
//     uint32 private constant DEST_EID = 30184;
//     uint256 private constant DEST_CHAIN_ID = 8453;
//     address private constant BASE_OFT_TOKEN_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
//     address private constant BASE_STARGATE_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
//     address private constant BASE_UNISWAP_ROUTER_V2 = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
//     address private constant WETH = 0x4200000000000000000000000000000000000006;

//     // Events
//     event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);

//     function setUp() public {
//         string memory destRpcUrl = vm.envString("BASE_RPC_URL");
//         destForkId = vm.createSelectFork(destRpcUrl); // Create fork at the latest block
//         baseConfig = new HelperConfig();
//         HelperConfig.NetworkConfig memory baseNetworkConfig = baseConfig.getConfig();
//         owner = baseNetworkConfig.account;
//         vm.prank(owner);
//         // TODO: Deploy eBTC
//         baseChainCoordinator = new BaseChainCoordinator(
//             BASE_STARGATE_ENDPOINT_V2, // endpoint
//             address(0), // eBTC
//             owner // owner
//         );

//         string memory rpcUrl = vm.envString("OPTIMISM_RPC_URL");
//         sourceForkId = vm.createSelectFork(rpcUrl);
//         homeConfig = new HelperConfig();
//         lzHelper = new LayerZeroV2Helper();

//         // Deploy CrossChainDexSender
//         vm.prank(owner);
//         homeChainCoordinator = new HomeChainCoordinator(OPTIMISM_ENDPOINT_V2, owner);

//         // Fund the contract
//         vm.deal(address(this), 100 ether);
//         vm.deal(owner, 100 ether);
//     }

//     function testSetReceiver() public {
//         // Set the receiver
//         bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));
//         vm.prank(owner);
//         homeChainCoordinator.setPeer(DEST_EID, receiver);

//         // Assert that the receiver is set correctly
//         assertEq(homeChainCoordinator.peers(DEST_EID), receiver);
//     }

//     function testSendMessage() public {
//         // Set the receiver first
//         bytes32 sender = bytes32(uint256(uint160(address(homeChainCoordinator))));
//         bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));

//         // Set receivers and peers on both chains
//         vm.selectFork(sourceForkId);
//         vm.prank(owner);
//         homeChainCoordinator.setPeer(DEST_EID, receiver);

//         // Set up peer on destination chain
//         vm.selectFork(destForkId);
//         vm.prank(owner);
//         baseChainCoordinator.setPeer(OP_EID, sender);

//         // Back to source chain for sending message
//         vm.selectFork(sourceForkId);

//         // Send a message
//         bytes memory message =
//             hex"0200000000010198125705e23e351caccd7435b4d41ee3b685b460b7121be3b0f5089dd507a7b50300000000ffffffff04e803000000000000225120c35241ec07fba00f5ea6e81b63f5af8087dc5e329a01d4ef9d8d6b498abcd902881300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a30001441588441c41d5528cc6afa3a2a732afeca9e9452000800000000000003e80004000000050008000000000001869fd72f000000000000160014d6a279dc882b830c5562b49e3e25bf3c5767ab73024730440220398d6577bc7adbe65b23e7ca7819d5bd28ed5b919108a89d3f607ddf8b78ca0e02204085b4547b7555dcf3be79e64ece0dfdc469a21c301bf05c4c36a616b1346f7901210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb00000000"; // Empty message
//         console2.log("Sending message from test");

//         // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
//         //     .addExecutorNativeDropOption(200000, 0) // gas limit: 200k, value: 0
//         //         // gas limit: 200k, value: 0
//         //     .build();
//         bytes memory options = hex"0003010011010000000000000000000000000000c350";
//         vm.recordLogs();
//         homeChainCoordinator.sendMessage{value: 0.2 ether}(DEST_EID, message, options);
//         console2.log("Message sent");

//         // Process the message on destination chain
//         Vm.Log[] memory logs = vm.getRecordedLogs();
//         // Is there a way to console logs here?
//         lzHelper.help(BASE_STARGATE_ENDPOINT_V2, destForkId, logs);

//         bytes memory bytesMessage = abi.encode(message);
//         vm.selectFork(destForkId);
//         // assertNotEq(baseChainCoordinator.lastExecutor(), address(0));
//         // assertEq(baseChainCoordinator.temp_message(), bytesMessage);
//     }

//     fallback() external payable {}
//     receive() external payable {}
// }
