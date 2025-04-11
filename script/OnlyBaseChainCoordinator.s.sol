// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title OnlyTaskManagerDeployer
 * @notice Script for deploying only the TaskManager contract
 * @dev Deploys a TaskManager contract with the specified parameters
 */
contract OnlyTaskManagerDeployer is Script {
    // Constants
    address internal constant EBTC_MANAGER = 0x252EF6f6d4618a4896D2736e56F26FC7FAD4d6a1;

    // Contract instances
    BaseChainCoordinator internal _baseChainCoordinator;

    // Network configurations
    HelperConfig.NetworkConfig internal _destNetworkConfig;

    // Fork IDs
    uint256 internal _destForkId;

    function run() public {
        string memory srcRpcUrl = vm.envString("BSC_TESTNET_RPC_URL");
        _destForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        _destNetworkConfig = destConfig.getConfig();

        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");
        address owner = vm.addr(privateKey);

        vm.startBroadcast(privateKey);
        _baseChainCoordinator = new BaseChainCoordinator(
            _destNetworkConfig.endpoint, // endpoint
            owner, // owner
            EBTC_MANAGER, // eBTCManager,
            _destNetworkConfig.chainEid, // chainEid
            40217 // HomeChainCoordinator chainEid on Holesky
        ); // HomeChainCoordinator chainEid);
        console.log("Deployed TaskManager", address(_baseChainCoordinator));
        vm.stopBroadcast();
    }
}
