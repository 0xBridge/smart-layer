// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {eBTCManager} from "../src/eBTCManager.sol";
import {eBTC} from "../src/eBTC.sol";
import {eBTCMock} from "../src/mocks/eBTCMock.sol";

contract BaseChainCoordinatorTest is Script {
    HomeChainCoordinator private homeChainCoordinator;
    BaseChainCoordinator private baseChainCoordinator;
    BitcoinLightClient private btcLightClient;
    eBTCManager private eBTCManagerInstance;
    // eBTC private eBTCToken;
    eBTCMock private eBTCToken;

    HelperConfig.NetworkConfig private srcNetworkConfig;
    HelperConfig.NetworkConfig private destNetworkConfig;

    address private owner = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
    address private constant aggregator = 0x534e9B3EA1F77f687074685a5F7C8a568eF6D586;

    uint256 private sourceForkId;
    uint256 private destForkId;

    // Bitcoin SPV Testnet constants (Block #68741)
    uint32 private constant blockVersion = 536870912;
    uint32 private constant blockTimestamp = 1738656278;
    uint32 private constant difficultyBits = 486604799;
    uint32 private constant nonce = 4059174314;
    uint32 private constant height = 68741;
    bytes32 private constant prevBlock = 0x000000000000123625879059bc5035363bcc5d4dde895f427bbe9b8866d51d7f;
    bytes32 private constant merkleRoot = 0x58863b7cb847987c2a0f711e1bb3b910d9a748636c6a7c34cf865ab9ac2048ac;

    function run() public {
        string memory destRpcUrl = vm.envString("CORE_TESTNET_RPC_URL");
        destForkId = vm.createSelectFork(destRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        destNetworkConfig = destConfig.getConfig();

        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");
        // owner = address(uint160(privateKey));
        console.log("Owner: ", owner);
        vm.startBroadcast(privateKey);
        // Deploy the eBTCManager contract
        eBTCManagerInstance = new eBTCManager(owner);
        console.log("Deployed eBTCManager");

        // Deploy the base chain coordinator
        baseChainCoordinator = new BaseChainCoordinator(
            destNetworkConfig.endpoint, // endpoint
            owner, // owner
            address(eBTCManagerInstance) // eBTCManager
        );
        console.log("Deployed BaseChainCoordinator");

        // Deploy implementation and proxy for eBTC using ERC1967Proxy
        // eBTC eBTCImplementation = new eBTC();
        // bytes memory initData = abi.encodeWithSelector(eBTC.initialize.selector, address(eBTCManagerInstance));
        // ERC1967Proxy proxy = new ERC1967Proxy(address(eBTCImplementation), initData);
        // eBTCToken = eBTC(address(proxy));
        eBTCToken = new eBTCMock(address(eBTCManagerInstance)); // TODO: Remove this and use the above code
        console.log("Deployed eBTC and created proxy");

        // Set the minter role for the eBTCManager contract
        eBTCManagerInstance.setMinterRole(address(baseChainCoordinator));
        console.log("Set minter role for eBTCManager");
        eBTCManagerInstance.setEBTC(address(eBTCToken));
        console.log("Set eBTC address in eBTCManager");
        vm.stopBroadcast();

        string memory srcRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        sourceForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();
        bytes32 receiver = bytes32(uint256(uint160(address(baseChainCoordinator))));
        console.logBytes32(receiver);

        vm.startBroadcast(owner);
        // Deploy implementation and proxy for BitcoinLightClient using ERC1967Proxy
        BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
        bytes memory lightClientInitData = abi.encodeWithSelector(
            BitcoinLightClient.initialize.selector,
            owner,
            blockVersion,
            blockTimestamp,
            difficultyBits,
            nonce,
            height,
            prevBlock,
            merkleRoot
        );
        ERC1967Proxy lightClientProxy = new ERC1967Proxy(address(bitcoinLightClientImplementation), lightClientInitData);
        btcLightClient = BitcoinLightClient(address(lightClientProxy));
        console.log("Deployed BitcoinLightClient and created proxy");

        homeChainCoordinator = new HomeChainCoordinator(address(btcLightClient), srcNetworkConfig.endpoint, owner);
        console.log("Deployed HomeChainCoordinator");
        homeChainCoordinator.setPeer(destNetworkConfig.chainEid, receiver);
        console.log("Set peer in HomeChainCoordinator");
        homeChainCoordinator.transferOwnership(aggregator);
        console.log("Transferred ownership of HomeChainCoordinator");
        vm.stopBroadcast();

        vm.selectFork(destForkId);
        bytes32 sender = bytes32(uint256(uint160(address(homeChainCoordinator))));
        vm.startBroadcast(owner);
        baseChainCoordinator.setPeer(srcNetworkConfig.chainEid, sender);
        console.log("Set peer in BaseChainCoordinator");
        vm.stopBroadcast();
    }
}
