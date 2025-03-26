// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ISignatureUtils} from
    "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

// Create interfaces for the L1 and L2 factory contracts based on the methods 0x14d6ec60 and 0x8a64a2e0 respectively
interface IL1AVSFactory {
    function deploy(L1AVSFactoryParams calldata params) external payable;

    struct L1AVSFactoryParams {
        string avsName; // test-0xBridge
        address someAddress; // ZERO_ADDRESS (Not sure what this is)
        address tokenBackingAVS; // WETH in our case
        uint256 chainId; // chain ID of the destination chain (Amoy)
    }
}

interface IL2AVSFactory {
    function functionName(L2AVSFactoryParams calldata params) external payable;

    struct L2AVSFactoryParams {
        string avsName; // test-0xBridge
        address someAddress; // ZERO_ADDRESS (Not sure what this is)
        address tokenBackingAVS; // WETH in our case
        uint256 someUint256; // 0 (Not sure what this is)
        uint256 chainId; // chain ID of the source chain (Holesky)
    }
}

contract AVSDeployerScript is Script {
    // Holesky addresses
    address private constant ZERO_ADDRESS = address(0);
    address private constant WETH_ADDRESS = 0x94373a4919B3240D86eA41593D5eBa789FEF3848;

    // Contract addresses
    address private constant L1_FACTORY_ADDRESS = 0xf053F341C021F57f4a17C25476DF4761b0728D53;
    address private constant L2_FACTORY_ADDRESS = 0xc2a881Dd3e6a9C21C18A998E47f90120BC9D87Aa;

    // Configurable parameters
    string private constant AVS_NAME = "test-0xBridge";
    uint256 private constant DESTINATION_CHAIN_ID = 80002; // 0x13882
    uint256 private constant SOURCE_CHAIN_ID = 17000; // 0x4268
    uint256 private constant SOME_UINT256 = 0;

    // Amount to transfer when initializing bridge
    uint256 private constant L1_TRANSFER_AMOUNT = 1 ether;
    uint256 private constant L2_TRANSFER_AMOUNT = 10 ether;

    function setUp() public {
        // Get the required hardcoded values from env or constants above
    }

    function run() public {
        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast();

        // Deploy L1 AVS contracts
        IL1AVSFactory l1Factory = IL1AVSFactory(L1_FACTORY_ADDRESS);
        IL1AVSFactory.L1AVSFactoryParams memory l1Params = IL1AVSFactory.L1AVSFactoryParams({
            avsName: AVS_NAME,
            someAddress: ZERO_ADDRESS,
            tokenBackingAVS: WETH_ADDRESS,
            chainId: DESTINATION_CHAIN_ID
        });

        l1Factory.deploy{value: L1_TRANSFER_AMOUNT}(l1Params); // TODO: Call this via function selector
        // console.log("L1 Bridge deployed at:", deployedL1Bridge);

        // Deploy L2 AVS contracts
        IL2AVSFactory l2Factory = IL2AVSFactory(L2_FACTORY_ADDRESS);
        IL2AVSFactory.L2AVSFactoryParams memory l2Params = IL2AVSFactory.L2AVSFactoryParams({
            avsName: AVS_NAME,
            someAddress: ZERO_ADDRESS,
            tokenBackingAVS: WETH_ADDRESS,
            someUint256: SOME_UINT256,
            chainId: SOURCE_CHAIN_ID
        });

        l2Factory.functionName{value: L2_TRANSFER_AMOUNT}(l2Params); // TODO: Call this via function selector
        console.log("L2 Bridge initialized with 0.8 POL");

        vm.stopBroadcast();
        console.log("Bridge deployment completed successfully!");
    }
}
