// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";

contract DeployBitcoinLightClient is Script {
    function run() external {
        // Start the broadcast to deploy the contract
        vm.startBroadcast();

        // Bitcoin block header #878349: https://btcscan.org/block/000000000000000000023469320004d4838dc630ff7be3094b6f69c224ff0139
        uint32 version = 536879104;
        uint32 timestamp = 1736341093;
        uint32 difficultyBits = 386043996;
        uint32 nonce = 609056055;
        uint32 height = 878349;
        bytes32 prevBlock = 0x0000000000000000000019f09b809caeb8e7dbc8661dbebd642a16f061b3d0bc;
        bytes32 merkleRoot = 0x52ff3457a60ec7fd17388143465c209c3ddf665a2c616e32184c301cf1d20fed;

        // Deploy the LightClient contract
        BitcoinLightClient lightClient =
            new BitcoinLightClient(version, timestamp, difficultyBits, nonce, height, prevBlock, merkleRoot);

        // Log the deployed contract address
        console.log("LightClient deployed to:", address(lightClient));

        // Stop the broadcast
        vm.stopBroadcast();
    }
}
