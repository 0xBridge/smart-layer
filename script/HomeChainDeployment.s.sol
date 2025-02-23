// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AVSExtension} from "../src/AVSExtension.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {Utils} from "./utils/Utils.sol";

contract HomeChainCoordinatorDeployment is Script, Utils {
    // Main contracts
    AVSExtension private avsExtension;
    HomeChainCoordinator private homeChainCoordinator;
    BitcoinLightClient private btcLightClient;
    address private owner; // 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E
    address private generator; // 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE
    address private aggregator; // 0x534e9B3EA1F77f687074685a5F7C8a568eF6D586

    // Network config constants (Note: The below two values will change based on destination network)
    uint32 private constant CORE_DEST_EID = 40153;
    // uint32 private constant BNB_DEST_EID = 40102;
    bytes32 private constant CORE_TESTNET_RECEIVER = 0x000000000000000000000000bac2b1cfa58fe1bb033dfb909b5dbd96a19bbed9; // Deployed on CoreDAO Testnet
    // bytes32 private constant BNB_TESTNET_RECEIVER = bytes32(uint256(uint160()));
    address private constant ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3; // Deployed on Holesky

    // Network configs
    HelperConfig.NetworkConfig private srcNetworkConfig;

    // Put bitcoin light client init data as constants here for the genesis block
    uint32 private constant blockVersion = 536870912;
    uint32 private constant blockTimestamp = 1738656278;
    uint32 private constant difficultyBits = 486604799;
    uint32 private constant nonce = 4059174314;
    uint32 private constant height = 68741;
    bytes32 private constant prevBlock = 0x000000000000123625879059bc5035363bcc5d4dde895f427bbe9b8866d51d7f;
    bytes32 private constant merkleRoot = 0x58863b7cb847987c2a0f711e1bb3b910d9a748636c6a7c34cf865ab9ac2048ac;

    function run() public {
        // Get the environment variables
        // Get the private key and address of the deployer / owner
        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");
        owner = vm.addr(privateKey);

        // Get the private key and address of the performer / generator
        uint256 generatorPrivateKey = vm.envUint("GENERATOR_PRIVATE_KEY");
        generator = vm.addr(generatorPrivateKey);

        // Get the private key and address of the aggregator
        uint256 aggregatorPrivateKey = vm.envUint("AGGREGATOR_PRIVATE_KEY");
        aggregator = vm.addr(aggregatorPrivateKey);

        // Get home chain network - In case we change this to Holesky, we need to change this url to HOLESKY_TESTNET_RPC_URL
        string memory rpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);
        HelperConfig config = new HelperConfig();
        srcNetworkConfig = config.getConfig();

        vm.startBroadcast(privateKey);
        // Deploy Bitcoin Light Client and HomeChainCoordinator
        BitcoinLightClient bitcoinLightClientImplementation = new BitcoinLightClient();
        console.log("Deployed BitcoinLightClient");
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
        console.log("Deployed lightClientProxy and created proxy");
        btcLightClient = BitcoinLightClient(address(lightClientProxy));

        // Deploy HomeChainCoordinator
        homeChainCoordinator = new HomeChainCoordinator(address(btcLightClient), srcNetworkConfig.endpoint, owner);
        console.log("Deployed HomeChainCoordinator");
        // Set destination peer address (Without this, the HomeChainCoordinator won't be able to send messages to the destination network)
        homeChainCoordinator.setPeer(CORE_DEST_EID, CORE_TESTNET_RECEIVER);
        console.log("SetPeer on HomeChainCoordinator");
        // homeChainCoordinator.setPeer(BNB_DEST_EID, BNB_TESTNET_RECEIVER);
        // Transfer ownership to aggregator (as of this point, the message will come directly from the aggregator and not the AVSExtension)
        homeChainCoordinator.transferOwnership(aggregator);
        console.log("Transferred ownership of HomeChainCoordinator");
        // Deploy AVSExtension
        avsExtension = new AVSExtension(owner, generator, ATTESTATION_CENTER, address(homeChainCoordinator));
        console.log("Deployed AVSExtension");
        vm.stopBroadcast();

        // WRITE JSON DATA
        string memory parent_object = "parent object";

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "avsExtension", address(avsExtension));
        string memory deployed_addresses_output =
            vm.serializeAddress(deployed_addresses, "homeChainCoordinator", address(homeChainCoordinator));

        // serialize all the data
        string memory finalJson = vm.serializeString(parent_object, deployed_addresses, deployed_addresses_output);

        writeOutput(finalJson, "avs_deployment_output");
    }
}
