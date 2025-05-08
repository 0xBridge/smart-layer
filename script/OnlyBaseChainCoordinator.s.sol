// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {eBTCManager} from "../src/eBTCManager.sol"; // Assuming path
import {eBTC} from "../src/eBTC.sol"; // Assuming path
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title OnlyBaseChainCoordinatorDeployer
 * @notice Script for deploying eBTC, eBTCManager, and BaseChainCoordinator contracts
 * @dev Deploys contracts with the specified parameters
 */
contract OnlyBaseChainCoordinatorDeployer is Script {
    // Constants
    uint32 internal constant HOLESKY_CHAIN_EID = 40217; // Holesky LayerZero Endpoint ID
    uint256 internal constant DEFAULT_GAS_PRICE = 1_000_000_000; // 1 Gwei

    // Contract instances
    BaseChainCoordinator internal _baseChainCoordinator;
    eBTCManager internal _eBTCManager;
    eBTC internal _eBTC;

    // Network configurations
    HelperConfig.NetworkConfig internal _destNetworkConfig;

    // Fork IDs
    uint256 internal _destForkId;

    function run() public {
        string memory srcRpcUrl = vm.envString("CORE_TESTNET_RPC_URL");
        _destForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        _destNetworkConfig = destConfig.getConfig();

        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");
        address owner = vm.addr(privateKey);

        vm.txGasPrice(DEFAULT_GAS_PRICE); // Set gas price for subsequent transactions
        vm.startBroadcast(privateKey);

        address eBTCManagerAddress = _deployEBTCContracts(owner);

        _baseChainCoordinator = new BaseChainCoordinator(
            _destNetworkConfig.endpoint, // endpoint
            owner, // owner
            eBTCManagerAddress, // eBTCManager
            _destNetworkConfig.chainEid, // chainEid
            HOLESKY_CHAIN_EID // HomeChainCoordinator chainEid on Holesky
        );
        console.log("Deployed BaseChainCoordinator", address(_baseChainCoordinator));
        vm.stopBroadcast();
    }

    function _deployEBTCContracts(address owner) internal returns (address eBTCManagerAddress) {
        console.log("Deploying eBTCManager contract...");
        _eBTCManager = new eBTCManager(owner); // Assumes eBTCManager constructor takes owner
        eBTCManagerAddress = address(_eBTCManager);
        console.log("Deployed eBTCManager at:", eBTCManagerAddress);

        console.log("Deploying eBTC implementation contract...");
        eBTC eBTCImplementation = new eBTC(); // Assumes eBTC has a parameterless constructor for implementation
        console.log("Deployed eBTC implementation at:", address(eBTCImplementation));

        bytes memory initData = abi.encodeCall(eBTC.initialize, eBTCManagerAddress); // Assumes eBTC.initialize(address eBTCManager)
        ERC1967Proxy proxy = new ERC1967Proxy(address(eBTCImplementation), initData);
        _eBTC = eBTC(address(proxy));
        console.log("Deployed eBTC proxy at:", address(_eBTC));

        _eBTCManager.setEBTC(address(_eBTC)); // Assumes eBTCManager has setEBTC(address ebtcToken)
        console.log("Set eBTC address in eBTCManager");

        return eBTCManagerAddress;
    }
}
