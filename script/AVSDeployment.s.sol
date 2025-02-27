// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {eBTCManager} from "../src/eBTCManager.sol";
import {AVSExtension} from "../src/AVSExtension.sol";
import {eBTC} from "../src/eBTC.sol";
import {eBTCMock} from "../src/mocks/eBTCMock.sol";

/**
 * @title AVSDeployment
 * @notice Script for deploying all contracts needed for the base chain functionality
 * @dev Sets up the required contracts and configures their relationships
 */
contract AVSDeployment is Script {
    // Contract instances
    AVSExtension internal _avsExtension;
    HomeChainCoordinator internal _homeChainCoordinator;
    BaseChainCoordinator internal _baseChainCoordinator;
    BitcoinLightClient internal _btcLightClient;
    eBTCManager internal _eBTCManagerInstance;
    eBTC internal _eBTCToken;

    // Network configurations
    HelperConfig.NetworkConfig internal _srcNetworkConfig;
    HelperConfig.NetworkConfig internal _destNetworkConfig;

    // Constants
    address internal constant OWNER = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
    address internal constant AGGREGATOR = 0x534e9B3EA1F77f687074685a5F7C8a568eF6D586;
    address internal constant GENERATOR = 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE;
    address internal constant ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;

    // Fork IDs
    uint256 internal _sourceForkId;
    uint256 internal _destForkId;

    // Bitcoin SPV Testnet constants (Block #68741)
    uint32 internal constant BLOCK_VERSION = 536870912;
    uint32 internal constant BLOCK_TIMESTAMP = 1738656278;
    uint32 internal constant DIFFICULTY_BITS = 486604799;
    uint32 internal constant NONCE = 4059174314;
    uint32 internal constant HEIGHT = 68741;
    bytes32 internal constant PREV_BLOCK = 0x000000000000123625879059bc5035363bcc5d4dde895f427bbe9b8866d51d7f;
    bytes32 internal constant MERKLE_ROOT = 0x58863b7cb847987c2a0f711e1bb3b910d9a748636c6a7c34cf865ab9ac2048ac;

    /**
     * @notice Main deployment function
     * @dev Deploys and configures all necessary contracts on both source and destination chains
     */
    function run() public {
        string memory destRpcUrl = vm.envString("CORE_TESTNET_RPC_URL");
        _destForkId = vm.createSelectFork(destRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        _destNetworkConfig = destConfig.getConfig();

        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        _eBTCManagerInstance = new eBTCManager(OWNER);
        console.log("Deployed eBTCManager", address(_eBTCManagerInstance));
        _baseChainCoordinator = new BaseChainCoordinator(
            _destNetworkConfig.endpoint, // endpoint
            OWNER, // owner
            address(_eBTCManagerInstance), // eBTCManager,
            _destNetworkConfig.chainEid // chainEid
        );
        console.log("Deployed BaseChainCoordinator", address(_baseChainCoordinator));
        eBTC eBTCImplementation = new eBTC();
        bytes memory initData = abi.encodeWithSelector(eBTC.initialize.selector, address(_eBTCManagerInstance));
        ERC1967Proxy proxy = new ERC1967Proxy(address(eBTCImplementation), initData);
        _eBTCToken = eBTC(address(proxy));
        console.log("Deployed eBTC and created proxy", address(_eBTCToken));
        _eBTCManagerInstance.setMinterRole(address(_baseChainCoordinator));
        console.log("Set minter role for eBTCManager");
        _eBTCManagerInstance.setEBTC(address(_eBTCToken));
        console.log("Set eBTC address in eBTCManager");
        vm.stopBroadcast();

        string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
        _sourceForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        _srcNetworkConfig = srcConfig.getConfig();
        bytes32 receiver = bytes32(uint256(uint160(address(0x2908ba527aE590F9C7c5fCcDaC47598E28179Cf4))));
        console.logBytes32(receiver);

        vm.startBroadcast(privateKey);
        BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
        bytes memory lightClientInitData = abi.encodeWithSelector(
            BitcoinLightClient.initialize.selector,
            OWNER,
            BLOCK_VERSION,
            BLOCK_TIMESTAMP,
            DIFFICULTY_BITS,
            NONCE,
            HEIGHT,
            PREV_BLOCK,
            MERKLE_ROOT
        );
        ERC1967Proxy lightClientProxy = new ERC1967Proxy(address(bitcoinLightClientImplementation), lightClientInitData);
        _btcLightClient = BitcoinLightClient(address(lightClientProxy));
        console.log("Deployed BitcoinLightClient and created proxy", address(_btcLightClient));

        _homeChainCoordinator = new HomeChainCoordinator(
            address(_btcLightClient), _srcNetworkConfig.endpoint, OWNER, _srcNetworkConfig.chainEid
        );
        console.log("Deployed HomeChainCoordinator", address(_homeChainCoordinator));
        _homeChainCoordinator.setPeer(_destNetworkConfig.chainEid, receiver);
        console.log("Set peer in HomeChainCoordinator");
        _homeChainCoordinator.transferOwnership(AGGREGATOR);
        console.log("Transferred ownership of HomeChainCoordinator");
        _avsExtension = new AVSExtension(OWNER, GENERATOR, ATTESTATION_CENTER, address(_homeChainCoordinator));
        console.log("Deployed AVSExtension", address(_avsExtension));
        vm.stopBroadcast();

        vm.selectFork(_destForkId);
        console.log("Entered the last piece");
        bytes32 sender = bytes32(uint256(uint160(address(_homeChainCoordinator))));
        vm.startBroadcast(privateKey);
        _baseChainCoordinator.setPeer(_srcNetworkConfig.chainEid, sender);
        console.log("Set peer in BaseChainCoordinator");
        vm.stopBroadcast();
    }
}
