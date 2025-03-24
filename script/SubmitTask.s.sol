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
    address internal constant ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;

    /**
     * @notice Main execution function
     * @dev Submits a task and distributes rewards
     */
    function run() external {
        string memory rpcUrl = vm.envString("AMOY_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Set up private keys and derive addresses
        uint256 privateKeyGenerator = vm.envUint("GENERATOR_PRIVATE_KEY"); // Should have been Aggregator address private key
        uint256 privateKeyAvsGovernanceOwner = vm.envUint("OWNER_PRIVATE_KEY");

        // Create the AttestationCenter contract instance
        IAttestationCenter attestationCenter = IAttestationCenter(ATTESTATION_CENTER);

        // Create the task info
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "Just putting any random string here.",
            data: hex"000000008616134584b18a2e16e2b6f4b6f8acc7a1a975c2a8c6f8b10493e260", // hex bytes data
            taskPerformer: 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE, // Generator / Performer address
            taskDefinitionId: 0
        });

        // Signature data (Commented as it seems to be a placeholder or example)
        bytes memory tpSignature =
            hex"b8490b65ed3a418c1026b06c9984381ab099dc946981aa282e8eac2ccaf78c7f6ad3b6f01de81f29c21ed7ad974063785ef38e153c501dc0b3125ae5a9e8cd5a1b";
        uint256[2] memory taSignature = [
            20150624192400228108359345405435493754751152575474227883524848041839664309077,
            1082501311440838732190290197012581182681773299437476198311483876744319338514
        ];
        uint256[] memory attestersIds = new uint256[](2);
        attestersIds[0] = 3;
        attestersIds[1] = 4;

        // Start the broadcast as aggregator
        vm.startBroadcast(privateKeyGenerator);

        // Submit the task
        attestationCenter.submitTask(
            taskInfo,
            IAttestationCenter.EcdsaTaskSubmissionDetails({
                isApproved: true,
                tpSignature: tpSignature,
                taSignature: taSignature,
                attestersIds: attestersIds
            })
        );

        // Stop the broadcast
        vm.stopBroadcast();

        // Start the broadcast as AVS governance owner
        vm.startBroadcast(privateKeyAvsGovernanceOwner);

        // Distribute rewards
        attestationCenter.requestBatchPayment();

        // Stop the broadcast
        vm.stopBroadcast();
    }
}
