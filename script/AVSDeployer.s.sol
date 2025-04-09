// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

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
    // Contract addresses
    string private constant AVS_NAME = "test-0xBridge-new"; // NOTE: This should be changed to a unique name every time a new AVS is deployed
    uint256 private constant SOME_UINT256 = 0;
    address private constant ZERO_ADDRESS = address(0);

    // Selectors to be called based on the deployed txns (on L1 and L2)
    bytes4 private constant L1_SELECTOR = 0x14d6ec60;
    bytes4 private constant L2_SELECTOR = 0x8a64a2e0;

    // Amount to transfer when initializing bridges to the message handlers
    uint256 private constant L1_TRANSFER_AMOUNT = 1 ether;
    uint256 private constant L2_TRANSFER_AMOUNT = 2 ether;

    // Configurable parameters
    uint256 srcForkId;
    uint256 destForkId;
    HelperConfig.NetworkConfig srcNetworkConfig;
    HelperConfig.NetworkConfig destNetworkConfig;

    function run() public {
        // Create destination chain to be used for deployment later
        string memory destRpcUrl = vm.envString("AMOY_RPC_URL");
        destForkId = vm.createSelectFork(destRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        destNetworkConfig = destConfig.getConfig();

        // Set up source chain
        string memory srcRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        srcForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();

        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast(privateKey);

        // Create L1 AVS deployment params
        IL1AVSFactory.L1AVSFactoryParams memory l1Params = IL1AVSFactory.L1AVSFactoryParams({
            avsName: AVS_NAME,
            someAddress: ZERO_ADDRESS,
            tokenBackingAVS: srcNetworkConfig.weth,
            chainId: destNetworkConfig.chainId
        });

        // Convert l1Params to ABI-encoded bytes
        bytes memory l1ParamsEncoded = abi.encode(l1Params);
        callWithSelector(srcNetworkConfig.othenticFactory, L1_SELECTOR, l1ParamsEncoded, L1_TRANSFER_AMOUNT);
        vm.stopBroadcast();

        // Set up destination chain
        vm.selectFork(destForkId);

        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast(privateKey);

        // Create L2 AVS deployment params
        IL2AVSFactory.L2AVSFactoryParams memory l2Params = IL2AVSFactory.L2AVSFactoryParams({
            avsName: AVS_NAME,
            someAddress: ZERO_ADDRESS,
            tokenBackingAVS: srcNetworkConfig.weth, // This is srcNetworkConfig.weth only and not destNetworkConfig.weth
            someUint256: SOME_UINT256,
            chainId: srcNetworkConfig.chainId
        });

        // Convert l2Params to ABI-encoded bytes
        bytes memory l2ParamsEncoded = abi.encode(l2Params);
        callWithSelector(destNetworkConfig.othenticFactory, L2_SELECTOR, l2ParamsEncoded, L2_TRANSFER_AMOUNT);
        vm.stopBroadcast();
    }

    /**
     * @notice Sends a transaction to a contract using a function selector and encoded parameters
     * @param target The address of the contract to call
     * @param selector The 4-byte function selector
     * @param params The ABI-encoded parameters (without the selector)
     * @param value The amount of ETH to send with the call
     * @return success Whether the call was successful
     * @return returnData The data returned by the call
     */
    function callWithSelector(address target, bytes4 selector, bytes memory params, uint256 value)
        public
        payable
        returns (bool success, bytes memory returnData)
    {
        // Combine the selector with the encoded parameters
        bytes memory callData = abi.encodePacked(selector, params);

        // Execute the call and return the result
        (success, returnData) = target.call{value: value}(callData);

        if (!success) {
            // If call reverts, try to decode the revert reason
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            } else {
                revert("Call failed with no return data");
            }
        }
    }
}
