// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {HomeChainCoordinator} from "../../src/experimental/HomeChainCoordinator.sol";
import {BaseChainCoordinator} from "../../src/experimental/BaseChainCoordinator.sol";
import {HelperConfig} from "../../script/experimental/HelperConfig.s.sol";
import {IOAppCore} from "lib/devtools/packages/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {LayerZeroV2Helper} from "lib/pigeon/src/layerzero-v2/LayerZeroV2Helper.sol";
// import {OptionsBuilder} from "lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract CoordinatorHomeChainTest is Test {
    // using OptionsBuilder for bytes;

    LayerZeroV2Helper private lzHelper;
    HomeChainCoordinator private homeChainCoordinator;
    BaseChainCoordinator private baseChainCoordinator;
    HelperConfig private homeConfig;
    HelperConfig private baseConfig;
    address private usdc;

    address private owner;
    address private user;
    // address private receiver;
    uint256 private constant INITIAL_BALANCE = 100_000e6; // 1000_000 USDC
    uint256 private constant AMOUNT_TO_BRIDGE = 4000e6; // 4000 USDC
    uint32 private constant OP_EID = 30111;
    address private constant OPTIMISM_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;

    uint256 private sourceForkId;
    uint256 private destForkId;
    uint32 private constant DEST_EID = 30184;
    uint256 private constant DEST_CHAIN_ID = 8453;
    address private constant BASE_OFT_TOKEN_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address private constant BASE_STARGATE_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
    address private constant BASE_UNISWAP_ROUTER_V2 = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address private constant WETH = 0x4200000000000000000000000000000000000006;

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);

    function setUp() public {
        string memory destRpcUrl = vm.envString("BASE_RPC_URL");
        destForkId = vm.createSelectFork(destRpcUrl); // Create fork at the latest block
        baseConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory baseNetworkConfig = baseConfig.getConfig();
        owner = baseNetworkConfig.account;
        vm.prank(owner);
        baseChainCoordinator = new BaseChainCoordinator(
            BASE_STARGATE_ENDPOINT_V2, // endpoint
            owner // owner
        );

        string memory rpcUrl = vm.envString("OPTIMISM_RPC_URL");
        sourceForkId = vm.createSelectFork(rpcUrl);
        homeConfig = new HelperConfig();
        lzHelper = new LayerZeroV2Helper();

        // Deploy CrossChainDexSender
        vm.prank(owner);
        homeChainCoordinator = new HomeChainCoordinator(OPTIMISM_ENDPOINT_V2, owner);

        // Fund the contract
        vm.deal(address(this), 100 ether);
        vm.deal(owner, 100 ether);
    }

    function testSetReceiver() public {
        // Set the receiver
        bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));
        vm.prank(owner);
        homeChainCoordinator.setReceiver(DEST_EID, receiver);

        // Assert that the receiver is set correctly
        assertEq(homeChainCoordinator.receivers(DEST_EID), receiver);
    }

    function testSendMessage() public {
        // Set the receiver first
        bytes32 sender = bytes32(uint256(uint160(address(homeChainCoordinator))));
        bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));

        // Set receivers and peers on both chains
        vm.selectFork(sourceForkId);
        vm.prank(owner);
        homeChainCoordinator.setReceiver(DEST_EID, receiver);

        // Set up peer on destination chain
        vm.selectFork(destForkId);
        vm.prank(owner);
        baseChainCoordinator.setReceiver(OP_EID, sender);

        // Back to source chain for sending message
        vm.selectFork(sourceForkId);

        // Send a message
        string memory message = "Hello, World!";
        console2.log("Sending message from test");
        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50000, 0);
        bytes memory options = hex"0003010011010000000000000000000000000000c350";
        vm.recordLogs();
        homeChainCoordinator.sendMessage{value: 0.2 ether}(DEST_EID, message, options);
        console2.log("Message sent");

        // Process the message on destination chain
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Is there a way to console logs here?
        lzHelper.help(BASE_STARGATE_ENDPOINT_V2, destForkId, logs);

        bytes memory bytesMessage = abi.encode(message);
        vm.selectFork(destForkId);
        assertEq(baseChainCoordinator.temp_message(), bytesMessage);
    }

    fallback() external payable {}
    receive() external payable {}
}
