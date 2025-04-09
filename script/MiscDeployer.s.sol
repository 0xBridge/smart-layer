// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";

/**
 * @title MiscDeployer
 * @notice Script for deploying BitcoinLightClient and linking it to an existing HomeChainCoordinator
 * @dev This script can be used in scenarios where you need to update the light client separately
 */
contract MiscDeployer is Script {
    // Contract instances
    BitcoinLightClient internal _btcLightClient;
    HomeChainCoordinator internal _homeChainCoordinator;

    // Network configuration
    HelperConfig.NetworkConfig internal _networkConfig;

    // Constants
    address internal constant OWNER = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;

    // Bitcoin SPV Testnet constants (Block #75728)
    uint32 internal constant BLOCK_VERSION = 536870912;
    uint32 internal constant BLOCK_TIMESTAMP = 1743682039;
    uint32 internal constant DIFFICULTY_BITS = 486604799;
    uint32 internal constant NONCE = 3598052123;
    uint32 internal constant HEIGHT = 75728;
    bytes32 internal constant PREV_BLOCK = 0x0000000098fc0394363837d13a3075ec22a3006abd288f25967382614249e835;
    bytes32 internal constant MERKLE_ROOT = 0xe32d2d38030cfa35db3b74f80a68cc8f5f9281fa6306cb6ec1236b099b71cf13;

    /**
     * @notice Main deployment function for BitcoinLightClient
     * @dev Deploys and initializes the BitcoinLightClient
     */
    function run() public {
        string memory rpcUrl = vm.envString("AMOY_RPC_URL");
        vm.createSelectFork(rpcUrl);
        HelperConfig config = new HelperConfig();
        _networkConfig = config.getConfig();

        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        // Deploy BitcoinLightClient implementation
        BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
        console.log("Deployed BitcoinLightClient implementation", address(bitcoinLightClientImplementation));

        // Prepare initialization data for proxy
        bytes memory lightClientInitData = abi.encodeCall(
            BitcoinLightClient.initialize,
            (OWNER, BLOCK_VERSION, BLOCK_TIMESTAMP, DIFFICULTY_BITS, NONCE, HEIGHT, PREV_BLOCK, MERKLE_ROOT)
        );

        // Deploy proxy with implementation and init data
        ERC1967Proxy lightClientProxy = new ERC1967Proxy(address(bitcoinLightClientImplementation), lightClientInitData);
        _btcLightClient = BitcoinLightClient(address(lightClientProxy));
        console.log("Deployed BitcoinLightClient proxy at", address(_btcLightClient));

        vm.stopBroadcast();
    }
}
