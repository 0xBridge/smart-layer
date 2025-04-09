// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title OnlyTaskManagerDeployer
 * @notice Script for deploying only the TaskManager contract
 * @dev Deploys a TaskManager contract with the specified parameters
 */
contract OnlyTaskManagerDeployer is Script {
    // Contract instances
    TaskManager internal _taskManager;

    // Network configurations
    HelperConfig.NetworkConfig internal _srcNetworkConfig;

    // Constants
    address internal constant OWNER = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
    address internal constant GENERATOR = 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE;
    address internal constant ATTESTATION_CENTER = 0xf8858A9d9794C1A73272f21a7dB84471F491797F;
    address internal constant HOME_CHAIN_COORDINATOR = 0x1bc82fD583a5C614f3f228C9455753Bdf0290240;

    // Fork IDs
    uint256 internal _sourceForkId;

    function run() public {
        string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
        _sourceForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        _srcNetworkConfig = srcConfig.getConfig();

        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        _taskManager = new TaskManager(OWNER, GENERATOR, ATTESTATION_CENTER, HOME_CHAIN_COORDINATOR);
        console.log("Deployed TaskManager", address(_taskManager));
        vm.stopBroadcast();
    }
}
