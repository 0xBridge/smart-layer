// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {IAttestationCenter} from "../src/interfaces/IAttestationCenter.sol";

/**
 * @title SubmitTask
 * @notice Script to submit tasks to the Attestation Center
 * @dev Sets up task information and submits with signatures
 */
contract SubmitTask is Script {
    // Constants
    address internal constant ATTESTATION_CENTER = 0xEA40f823f46CB372Cf58C184a9Ee7ECCF0200f07;

    /**
     * @notice Main execution function
     * @dev Submits a task and distributes rewards
     */
    function run() external {
        string memory rpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Set up private keys and derive addresses
        uint256 privateKey = vm.envUint("AGGREGATOR_PRIVATE_KEY"); // Should have been Aggregator address private key
        uint256 privateKeyAvsGovernanceOwner = vm.envUint("OWNER_PRIVATE_KEY");

        // Create the AttestationCenter contract instance
        IAttestationCenter attestationCenter = IAttestationCenter(ATTESTATION_CENTER);

        // Create the task info
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "Random",
            data: hex"0000000000000000000000000000000000000000000000000000000000000001b0a97d6e5c2844480b0b6b025b68dee5f70d16938f31f2cc1854814605c2a4f9", // hex bytes data
            taskPerformer: 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE, // Generator / Task creator address
            taskDefinitionId: 0
        });

        // Signature data (Commented as it seems to be a placeholder or example)
        bytes memory tpSignature =
            hex"bfd5d696e42816bdfc9a86651af10ebc76c12052d78ac6819c6a9b9487f980ee64fcbe4747be2c820e3d74aeef0c6efa37eeb420a985c4d52b2a152c8e5af6101b";
        uint256[2] memory taSignature = [
            19565671344821917801848597049102853064663301028077529815173197353806345535554,
            20642961566332536318617767370272501731800998997438704887582871778001478237442
        ];
        uint256[] memory attestersIds = new uint256[](2);
        attestersIds[0] = 2;
        attestersIds[1] = 3;

        // Start the broadcast as aggregator
        vm.startBroadcast(privateKey);

        // Submit the task
        attestationCenter.submitTask(taskInfo, true, tpSignature, taSignature, attestersIds);

        // Stop the broadcast
        vm.stopBroadcast();

        // // Start the broadcast as AVS governance owner
        // vm.startBroadcast(privateKeyAvsGovernanceOwner);

        // // Distribute rewards
        // attestationCenter.requestBatchPayment();

        // // Stop the broadcast
        // vm.stopBroadcast();
    }
}
