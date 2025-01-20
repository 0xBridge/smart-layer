// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {CrossChainDexSender} from "../../src/experimental/CrossChainDexSender.sol";
import {CrossChainDexReceiver} from "../../src/experimental/CrossChainDexReceiver.sol";
import {HelperConfig} from "../../script/experimental/HelperConfig.s.sol";
import {IStargate} from "../../src/experimental/interfaces/IStargate.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {LayerZeroV2Helper} from "lib/pigeon/src/layerzero-v2/LayerZeroV2Helper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainDexSenderTest is Test {
    using SafeTransferLib for address;

    LayerZeroV2Helper private lzHelper;
    CrossChainDexSender private crossChainDexSender;
    CrossChainDexReceiver private crossChainDexReceiver;
    HelperConfig private config;
    address public usdc;

    address public owner;
    address public user;
    address public receiver;
    uint256 public constant INITIAL_BALANCE = 100_000e6; // 1000_000 USDC
    uint256 public constant AMOUNT_TO_BRIDGE = 4000e6; // 4000 USDC

    uint256 public destForkId;
    uint256 public constant DEST_CHAIN_ID = 8453;
    address public constant BASE_OFT_TOKEN_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant BASE_STARGATE_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant BASE_UNISWAP_ROUTER_V2 = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    function setUp() public {
        string memory destRpcUrl = vm.envString("BASE_RPC_URL");
        destForkId = vm.createSelectFork(destRpcUrl); // Create fork at the latest block
        crossChainDexReceiver = new CrossChainDexReceiver(
            makeAddr("TEMP_OWNER"), // owner
            BASE_OFT_TOKEN_USDC, // stargatePoolUsdc
            BASE_STARGATE_ENDPOINT_V2, // endpoint
            BASE_UNISWAP_ROUTER_V2 // routerV2
        );

        string memory rpcUrl = vm.envString("OPTIMISM_RPC_URL");
        vm.createSelectFork(rpcUrl);

        config = new HelperConfig();
        lzHelper = new LayerZeroV2Helper();
        HelperConfig.NetworkConfig memory networkConfig = config.getConfig();

        // Setup accounts
        owner = networkConfig.account;
        user = makeAddr("user");
        receiver = makeAddr("receiver");

        // Create instance of USDC
        usdc = networkConfig.usdc;
        deal(networkConfig.usdc, user, INITIAL_BALANCE, true);

        // Deploy CrossChainDexSender
        vm.prank(owner);
        crossChainDexSender = new CrossChainDexSender(owner, networkConfig.stargatePoolUsdc);
        console2.log("crossChainDexSender address: ", address(crossChainDexSender));

        // Setup user balance and approvals
        vm.deal(user, 100 ether); // For gas fees
    }

    function testCrossChainSwapSuccess() public {
        uint32 dstEid = config.chainId_endpointId(DEST_CHAIN_ID);

        // Approve spending
        vm.startPrank(user);
        usdc.safeApprove(address(crossChainDexSender), AMOUNT_TO_BRIDGE);

        // Get quote for bridge fees
        uint256 deadline = 1 hours;
        bytes memory _composeMsg = abi.encode(receiver, BASE_OFT_TOKEN_USDC, WETH, AMOUNT_TO_BRIDGE, deadline);
        (uint256 nativeFee,,) = crossChainDexSender.prepareTakeTaxi(dstEid, AMOUNT_TO_BRIDGE, user, _composeMsg);

        // Perform cross-chain swap
        vm.expectEmit(true, true, false, true);
        emit CrossChainDexSender.BridgeAsset(receiver, BASE_OFT_TOKEN_USDC, WETH, AMOUNT_TO_BRIDGE, dstEid);

        console2.log("nativeFee: ", nativeFee);
        console2.log("user balance: ", user.balance);
        uint256 amountOutMinDest = 1 ether;
        vm.recordLogs();
        crossChainDexSender.crossChainSwap{value: nativeFee}(
            receiver,
            address(crossChainDexReceiver),
            dstEid,
            AMOUNT_TO_BRIDGE,
            user,
            BASE_OFT_TOKEN_USDC,
            WETH,
            amountOutMinDest,
            deadline
        );
        console2.log("testCrossChainSwapSuccess came till here");
        vm.stopPrank();

        // Process the message on destination chain
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Is there a way to console logs here?
        lzHelper.help(BASE_STARGATE_ENDPOINT_V2, destForkId, logs);

        // Verify token transfer
        assertEq(usdc.balanceOf(user), INITIAL_BALANCE - AMOUNT_TO_BRIDGE);
        console2.log("Balance of receiver: ", usdc.balanceOf(receiver));
        vm.selectFork(destForkId);
        console2.log(
            "Balance of crossChainDexReceiver: ", IERC20(BASE_OFT_TOKEN_USDC).balanceOf(address(crossChainDexReceiver))
        );
        assertApproxEqRel(IERC20(BASE_OFT_TOKEN_USDC).balanceOf(address(crossChainDexReceiver)), AMOUNT_TO_BRIDGE, 1e16); // 1e16 implies 1%
    }

    function testRevertsOnInsufficientNativeFee() public {
        uint32 dstEid = config.chainId_endpointId(DEST_CHAIN_ID);

        vm.startPrank(user);
        usdc.safeApprove(address(crossChainDexSender), AMOUNT_TO_BRIDGE);

        uint256 deadline = 1 hours;
        bytes memory _composeMsg = abi.encode(receiver, BASE_OFT_TOKEN_USDC, WETH, AMOUNT_TO_BRIDGE, deadline);
        (uint256 nativeFee,,) = crossChainDexSender.prepareTakeTaxi(dstEid, AMOUNT_TO_BRIDGE, receiver, _composeMsg);

        console2.log("testRevertsOnInsufficientNativeFee came till here");
        vm.expectRevert();
        uint256 amountOutMinDest = 1 ether;
        crossChainDexSender.crossChainSwap{value: nativeFee - 1}(
            receiver,
            address(crossChainDexReceiver),
            dstEid,
            AMOUNT_TO_BRIDGE,
            user,
            BASE_OFT_TOKEN_USDC,
            WETH,
            amountOutMinDest,
            deadline
        );
        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.startPrank(owner);
        crossChainDexSender.pause();
        assertTrue(crossChainDexSender.paused());

        uint32 dstEid = config.chainId_endpointId(DEST_CHAIN_ID);
        uint256 amountOutMinDest = 1 ether;
        uint256 deadline = 1 hours;
        vm.expectRevert();
        crossChainDexSender.crossChainSwap(
            receiver,
            address(crossChainDexReceiver),
            dstEid,
            AMOUNT_TO_BRIDGE,
            user,
            BASE_OFT_TOKEN_USDC,
            WETH,
            amountOutMinDest,
            deadline
        );

        crossChainDexSender.unpause();
        assertFalse(crossChainDexSender.paused());
        vm.stopPrank();
    }

    function test_OnlyOwnerCanWithdrawDust() public {
        // Fund contract with ETH
        vm.deal(address(crossChainDexSender), 1 ether);

        // Try to withdraw as non-owner
        vm.prank(user);
        vm.expectRevert();
        crossChainDexSender.withdrawDust();

        // Withdraw as owner
        vm.prank(owner);
        uint256 balanceBefore = owner.balance;
        crossChainDexSender.withdrawDust();
        assertEq(owner.balance - balanceBefore, 1 ether);
    }

    function test_OnlyOwnerCanWithdrawDustTokens() public {
        // Fund contract with USDC
        uint256 fundingAmount = 1000 * 1e6;
        deal(usdc, address(crossChainDexSender), fundingAmount, true);
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        // Try to withdraw as non-owner
        vm.prank(user);
        vm.expectRevert();
        crossChainDexSender.withdrawDustTokens(tokens);

        // Withdraw as owner
        vm.prank(owner);
        crossChainDexSender.withdrawDustTokens(tokens);
        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + fundingAmount);
    }

    function test_CannotSwapWhenPaused() public {
        // Pause contract
        vm.prank(owner);
        crossChainDexSender.pause();

        // Try to swap when paused
        vm.prank(user);
        vm.expectRevert();
        crossChainDexSender.crossChainSwap(
            user, // tokenReceiver
            address(0x3), // composer
            1, // dstEid
            100 * 1e6, // amount
            address(0), // refundAddress
            address(0x4), // oftOnDestinationAddress
            address(0x5), // tokenOut
            95 * 1e6, // amountOutMinDest
            block.timestamp + 3600 // deadline
        );
    }

    function test_OnlyOwnerCanPauseAndUnpause() public {
        // Try to pause as non-owner
        vm.prank(user);
        vm.expectRevert();
        crossChainDexSender.pause();

        // Pause as owner
        vm.prank(owner);
        crossChainDexSender.pause();
        assertTrue(crossChainDexSender.paused());

        // Try to unpause as non-owner
        vm.prank(user);
        vm.expectRevert();
        crossChainDexSender.unpause();

        // Unpause as owner
        vm.prank(owner);
        crossChainDexSender.unpause();
        assertFalse(crossChainDexSender.paused());
    }
}
