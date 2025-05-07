// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";

/**
 * @title SendMessageScript
 * @notice Script to configure cross-chain communication between networks
 * @dev Sets up peer relationships between HomeChainCoordinator and BaseChainCoordinator
 */
contract SendMessageScript is Script {
    // Contract instances
    HomeChainCoordinator internal _homeChainCoordinator;
    BaseChainCoordinator internal _baseChainCoordinator;

    // Constants
    address internal constant HOME_CHAIN_COORDINATOR_ADDRESS = 0xEE35AB43127933562c65A7942cbf1ccAac4BE86F; // on Amoy
    address internal constant BASE_CHAIN_COORDINATOR_ADDRESS = 0x2908ba527aE590F9C7c5fCcDaC47598E28179Cf4; // on Sepolia

    // Chain identification
    uint32 internal constant SRC_EID = 40267; // Amoy
    uint32 internal constant DEST_EID = 40161; // Sepolia

    /**
     * @notice Main execution function
     * @dev Configures peer relationships between coordinators on different chains
     */
    function run() public {
        // Set up destination chain fork
        string memory destRpcUrl = vm.envString("SEPOLIA_RPC_URL");
        uint256 destForkId = vm.createSelectFork(destRpcUrl);

        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        // Create an instance of already deployed BaseChainCoordinator contract
        _baseChainCoordinator = BaseChainCoordinator(payable(BASE_CHAIN_COORDINATOR_ADDRESS));
        console.log("BaseChainCoordinator", address(_baseChainCoordinator));

        // Set HomeChainCoordinator contract address as peer on BaseChainCoordinator
        // Convert address to bytes32
        bytes32 receiver = bytes32(uint256(uint160(HOME_CHAIN_COORDINATOR_ADDRESS)));
        _baseChainCoordinator.setPeer(SRC_EID, receiver);
        vm.stopBroadcast();

        // Set up source chain fork
        string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
        uint256 srcForkId = vm.createSelectFork(srcRpcUrl);
        uint256 aggregatorPrivateKey = vm.envUint("AGGREGATOR_PRIVATE_KEY");
        vm.startBroadcast(aggregatorPrivateKey);

        // Create an instance of already deployed HomeChainCoordinator contract
        _homeChainCoordinator = HomeChainCoordinator(payable(HOME_CHAIN_COORDINATOR_ADDRESS));
        console.log("HomeChainCoordinator", address(_homeChainCoordinator));

        // Set BaseChainCoordinator contract address as peer on HomeChainCoordinator
        bytes32 baseChainReceiver = bytes32(uint256(uint160(BASE_CHAIN_COORDINATOR_ADDRESS)));
        _homeChainCoordinator.setPeer(DEST_EID, baseChainReceiver);
        vm.stopBroadcast();
    }
}
