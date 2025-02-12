// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint32 endpointId;
        address endpoint;
        address account;
    }

    // Constants
    address constant OWNER_WALLET = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;

    NetworkConfig public localNetworkConfig;

    constructor() {
        // Get current chainId
        uint256 chainId = block.chainid;

        // Read and parse network config for current chain
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/network-config.json");
        string memory json = vm.readFile(path);

        // Try to parse the network config for current chain
        try vm.parseJson(json, string.concat(".", vm.toString(chainId))) returns (bytes memory networkData) {
            // First try to decode the endpoint and endpointId
            address endpoint =
                abi.decode(vm.parseJson(json, string.concat(".", vm.toString(chainId), ".endpoint")), (address));
            uint32 endpointId =
                abi.decode(vm.parseJson(json, string.concat(".", vm.toString(chainId), ".endpointId")), (uint32));

            // Set the local network config
            localNetworkConfig = NetworkConfig({endpointId: endpointId, endpoint: endpoint, account: OWNER_WALLET});
        } catch {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() public view returns (NetworkConfig memory) {
        if (localNetworkConfig.endpoint == address(0)) {
            revert HelperConfig__InvalidChainId();
        }
        return localNetworkConfig;
    }
}
