// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title SendMessageScript
 * @notice Script to send a cross-chain message via the HomeChainCoordinator
 * @dev Uses real Bitcoin block data for the proof
 */
contract SendMessageScript is Script {
    // Contract instance
    HomeChainCoordinator internal _coordinator;

    // Constants - to be updated for each deployment
    address internal constant COORDINATOR_ADDRESS = 0xEE35AB43127933562c65A7942cbf1ccAac4BE86F; // HomeChainCoordinator contract address on Amoy
    bytes32 internal constant BLOCK_HASH = 0x00000000000078556c00dbcd6505af1b06293da2a2ce4077b36ae0ee7caff284; // Block hash
    bytes32 internal constant BTC_TXN_HASH = 0x0b050a87ba271963ba19dc5ab6a53b6dcf4b5c4f5852033ea92aa78030a9f381; // BTC transaction hash

    // PSBT data represents the Bitcoin transaction
    bytes internal constant PSBT_DATA =
        hex"020000000001018b1a4ac7b6fc2a0a58ea6345238faae0785115da71e15b46609caa440ec834b90100000000ffffffff04102700000000000022512038b619797eb282894c5e33d554b03e1bb8d81d6d30d3c1a164ed15c8107f0774e80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144e56a8e3757f167378b38269e1ca0e1a1f124c9e000800000000000003e800040000210500080000000000004e207b84000000000000160014d6a279dc882b830c5562b49e3e25bf3c5767ab7302483045022100b4957432ec426f9f66797305bf0c44d586674d48c260c3d059b81b65a473f717022025b2f1641234dfd3f27eafabdd68a2fa1a0ab286a5292664f7ad9c260aa1455701210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb00000000";

    /**
     * @notice Setup function for the script
     * @dev Initializes the coordinator contract instance
     */
    function setUp() public {
        _coordinator = HomeChainCoordinator(payable(COORDINATOR_ADDRESS));
    }

    /**
     * @notice Main execution function
     * @dev Sends a message with Merkle proof for a Bitcoin transaction
     */
    function run() public {
        uint256 aggregatorPrivateKey = vm.envUint("AGGREGATOR_PRIVATE_KEY");

        string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
        vm.createSelectFork(srcRpcUrl);

        vm.startBroadcast(aggregatorPrivateKey);

        // Prepare Merkle proof
        bytes32[] memory proof = new bytes32[](10);
        proof[0] = 0xfb32c9f4cdaba5ea5f3303d3dfe22ac0c309d6af77aace63c68ace550cfedfb1;
        proof[1] = 0x4a678c1094499218f041baabbc196ff021667415939726a39734fa802b3d96aa;
        proof[2] = 0x9acf24b0e1de1e79ef0e7b8a28a5e6d94a3202040f599456ecf7eded81bcc588;
        proof[3] = 0xe288ec65f626692d368a6aff2edf17826424c73cd2489ad4ff83be87e22b293b;
        proof[4] = 0x8b53855e621a58e70554aeb396ca29f2f8b83687011cdd5c6b89dc64f378b358;
        proof[5] = 0xab8ac27bd1f80f1a4e7bf8ab1ba6961647063e6014029f007399e569bed666e5;
        proof[6] = 0x903c0b71cf0d975a2d993437785e412b64c8200a9fb35fd977408259285cec4d;
        proof[7] = 0xa64bb1bdff4ad095eb56d76221ac4393d3217f498e48d9a8f6209e6aa053f884;
        proof[8] = 0x0b01bb3744d2ea2016bdb840f48853cfb6be6321db28320cf44c5172c27eb59b;
        proof[9] = 0xc37d0af040d573fbb7cdba6cd828ee51562fb88158a2e84e6e3cff50c1472be9;
        uint256 index = 28;

        // Prepare LayerZero options
        bytes memory optionType = abi.encodePacked(uint16(3));
        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(optionType, 200000, 0);
        console.logBytes(options);

        // Calculate required messaging fee
        // (uint256 nativeFee,) = coordinator.quote(BTC_TXN_HASH, psbtData, options, false);
        // console.log("Required native fee:", nativeFee);

        // Send the message
        _coordinator.sendMessage{value: 2.5 ether}(BLOCK_HASH, BTC_TXN_HASH, proof, index, PSBT_DATA, options);
        // coordinator.sendMessageFor{value: nativeFee}(0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E, BTC_TXN_HASH, options);

        vm.stopBroadcast();
    }
}
