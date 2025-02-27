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
        uint256 privateKeyAggregator = vm.envUint("PRIVATE_KEY_AGGREGATOR");
        address aggregator = vm.addr(privateKeyAggregator);
        uint256 privateKeyAvsGovernanceOwner = vm.envUint("PRIVATE_KEY_DEPLOYER");
        address avsGovernanceOwner = vm.addr(privateKeyAvsGovernanceOwner);

        // Create the AttestationCenter contract instance
        IAttestationCenter attestationCenter = IAttestationCenter(ATTESTATION_CENTER);

        // Start the broadcast as aggregator
        vm.startBroadcast(privateKeyAggregator);

        // Create the task info
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmSw9NHrsmjGa6971uzCygiWsiRBV9nnVF516N6T4pFfNh",
            data: hex"4920616d2049726f6e6d616e21", // hex bytes data
            taskPerformer: aggregator,
            taskDefinitionId: 0
        });

        // Signature data (Commented as it seems to be a placeholder or example)
        /*
        bytes memory tpSignature =
            hex"31c6056e4cb228a6cca69ab6a46e04745630cbc36b38bc2a5929f7e1f6e4a0df106d1fd512d96def96f4b87d2d6bb9b836f868511611b4a8e08f8a4dda7c56761c";
        uint256[2] memory taSignature = [
            9093911615789399830602974754443205710846914036477274464096283111600022727438,
            11541948654984445339530075522406573357857067838037210814544443461153759883923
        ];
        uint256[] memory attestersIds = new uint256[](2);
        attestersIds[0] = 3;
        attestersIds[1] = 4;
        
        // attestationCenter.submitTask(taskInfo, true, tpSignature, taSignature, attestersIds);
        */

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
