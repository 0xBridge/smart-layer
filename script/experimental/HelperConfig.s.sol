// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address endpoint;
        address account;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256[] private networks = [
        ETH_MAINNET_CHAIN_ID,
        ETH_SEPOLIA_CHAIN_ID,
        POLYGON_MAINNET_CHAIN_ID,
        ARB_SEPOLIA_CHAIN_ID,
        ARB_MAINNET_CHAIN_ID,
        BASE_MAINNET_CHAIN_ID,
        OP_MAINNET_CHAIN_ID
    ];

    uint256 constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant POLYGON_MAINNET_CHAIN_ID = 137;
    uint256 constant ARB_SEPOLIA_CHAIN_ID = 421614;
    uint256 constant ARB_MAINNET_CHAIN_ID = 42161;
    uint256 constant BASE_MAINNET_CHAIN_ID = 8453;
    uint256 constant OP_MAINNET_CHAIN_ID = 10;

    // Update the OWNER_WALLET to your burner wallet!
    address constant OWNER_WALLET = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
    // address constant FOUNDRY_DEFAULT_WALLET = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    // address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => uint32) public chainId_endpointId;
    mapping(uint32 endpointId => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/network-config.json");
        string memory json = vm.readFile(path);

        // Parse each network config from the JSON
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i];
            bytes memory networkData = vm.parseJson(json, string.concat(".", vm.toString(chainId)));

            NetworkConfig memory config = abi.decode(networkData, (NetworkConfig));
            uint32 endpointId =
                abi.decode(vm.parseJson(json, string.concat(".", vm.toString(chainId), ".endpointId")), (uint32));

            chainId_endpointId[chainId] = endpointId;
            networkConfigs[endpointId] = NetworkConfig({
                endpoint: config.endpoint,
                account: OWNER_WALLET // We'll keep this constant
            });
        }
    }

    function getConfig() public view returns (NetworkConfig memory) {
        uint32 endpointId = chainId_endpointId[block.chainid];
        return getConfigByEndpointId(endpointId);
    }

    function getConfigByEndpointId(uint32 endpointId) public view returns (NetworkConfig memory) {
        if (networkConfigs[endpointId].endpoint != address(0)) {
            return networkConfigs[endpointId];
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }
}
