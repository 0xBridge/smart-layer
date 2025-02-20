// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {IAttestationCenter} from "../src/interfaces/IAttestationCenter.sol";

contract SubmitTask is Script {
    function run() external {
        string memory rpcUrl = vm.envString("AMOY_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Set the private key and the contract address
        address ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;
        uint256 PRIVATE_KEY_AGGREGATOR = vm.envUint("PRIVATE_KEY_AGGREGATOR");
        address AGGREGATOR = vm.addr(PRIVATE_KEY_AGGREGATOR);
        uint256 PRIVATE_KEY_AVS_GOVERNANCE_OWNER = vm.envUint("PRIVATE_KEY_DEPLOYER");
        address AVS_GOVERNANCE_OWNER = vm.addr(PRIVATE_KEY_AVS_GOVERNANCE_OWNER);

        // Create the AttestationCenter contract
        IAttestationCenter attestationCenter = IAttestationCenter(ATTESTATION_CENTER);

        // Start the broadcast
        vm.startBroadcast(AGGREGATOR);

        // Create the task info
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmSw9NHrsmjGa6971uzCygiWsiRBV9nnVF516N6T4pFfNh",
            data: hex"4920616d2049726f6e6d616e21", // hex bytes data
            taskPerformer: AGGREGATOR,
            taskDefinitionId: 0
        });

        // Submit the task (TODO: Figure this part out)
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

        // Stop the broadcast
        vm.stopBroadcast();

        // Start the broadcast
        vm.startBroadcast(AVS_GOVERNANCE_OWNER);

        // Distribute rewards
        attestationCenter.requestBatchPayment(); // Deployer (AVS_MULTISIG_OWNER)

        // Stop the broadcast
        vm.stopBroadcast();
    }
}
