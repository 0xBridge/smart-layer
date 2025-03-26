// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";

/**
 * @title HelperConfig
 * @notice Configuration helper for network-specific settings
 * @dev Loads configuration from JSON files based on the current chain ID
 */
contract HelperConfig is Script {
    // Custom errors
    error HelperConfig__InvalidChainId();

    // Data structures
    struct NetworkConfig {
        uint32 chainEid;
        address endpoint;
        address account;
    }

    // Constants
    address internal constant OWNER_WALLET = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;

    // State variables
    NetworkConfig internal _localNetworkConfig;

    /**
     * @notice Contract constructor
     * @dev Loads network configuration based on current chain ID
     */
    constructor() {
        // Get current chainId
        uint256 chainId = block.chainid;
        _initNetworkConfig(chainId);
    }

    /**
     * @notice Inits the network configuration for the current chain from a JSON file
     * @param chainId Chain ID to set configuration for
     * @dev Reverts if chain ID is not found in the network json file
     */
    function _initNetworkConfig(uint256 chainId) internal {
        // Read and parse network config for current chain
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/network-config.json");
        string memory json = vm.readFile(path);

        // Try to parse the network config for current chain
        try vm.parseJson(json, string.concat(".", vm.toString(chainId))) returns (bytes memory) {
            // First try to decode the endpoint and chainEid
            address endpoint =
                abi.decode(vm.parseJson(json, string.concat(".", vm.toString(chainId), ".endpoint")), (address));
            uint32 chainEid =
                abi.decode(vm.parseJson(json, string.concat(".", vm.toString(chainId), ".chainEid")), (uint32));

            // Set the local network config
            _localNetworkConfig = NetworkConfig({chainEid: chainEid, endpoint: endpoint, account: OWNER_WALLET});
        } catch {
            revert HelperConfig__InvalidChainId();
        }
    }

    /**
     * @notice Gets the network configuration
     * @dev Reverts if chain ID is invalid or configuration is missing
     * @return Network configuration for the current chain
     */
    function getConfig() public view returns (NetworkConfig memory) {
        if (_localNetworkConfig.endpoint == address(0)) {
            revert HelperConfig__InvalidChainId();
        }
        return _localNetworkConfig;
    }
}
