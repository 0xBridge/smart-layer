// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";

contract SendMessageScript is Script {
    HomeChainCoordinator private homeChainCoordinator;
    BaseChainCoordinator private baseChainCoordinator;

    // Update these values according to your deployment
    address constant HOME_CHAIN_COORDINATOR_ADDRESS = 0xFd0e3af7503F07b06a69d5a35C4dc21501b9315f; // HomeChainCoordinator contract address on Amoy (destination == BSC)
    address constant BASE_CHAIN_COORDINATOR_ADDRESS = 0x7Ad135dC73bf483E74869e61B51442B54D498ab4; // BaseChainCoordinator contract address on BSC (source == Amoy)

    // Ethereum ID of the source chain
    uint32 constant srcEid = 40267; // Amoy
    uint32 constant destEid = 40102; // BSC

    function run() public {
        string memory destRpcUrl = vm.envString("BNB_TESTNET_RPC_URL");
        uint256 destForkId = vm.createSelectFork(destRpcUrl);

        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        // Create an instance of already deployed BaseChainCoordinator contract
        baseChainCoordinator = BaseChainCoordinator(BASE_CHAIN_COORDINATOR_ADDRESS);
        console.log("BaseChainCoordinator", address(baseChainCoordinator));
        // Set HomeChainCoordinator contract address as peer on BaseChainCoordinator
        // Convert address to bytes32
        bytes32 receiver = bytes32(uint256(uint160(HOME_CHAIN_COORDINATOR_ADDRESS)));
        baseChainCoordinator.setPeer(srcEid, receiver);
        vm.stopBroadcast();

        string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
        uint256 srcForkId = vm.createSelectFork(srcRpcUrl);
        uint256 aggregatorPrivateKey = vm.envUint("AGGREGATOR_PRIVATE_KEY");
        vm.startBroadcast(aggregatorPrivateKey);
        // Create an instance of already deployed HomeChainCoordinator contract
        homeChainCoordinator = HomeChainCoordinator(payable(HOME_CHAIN_COORDINATOR_ADDRESS));
        console.log("HomeChainCoordinator", address(homeChainCoordinator));
        // Set BaseChainCoordinator contract address as peer on HomeChainCoordinator
        bytes32 baseChainReceiver = bytes32(uint256(uint160(BASE_CHAIN_COORDINATOR_ADDRESS)));
        homeChainCoordinator.setPeer(destEid, baseChainReceiver);
        vm.stopBroadcast();
    }
}
