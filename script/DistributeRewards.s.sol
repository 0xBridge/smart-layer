// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {IAttestationCenter} from "../src/interfaces/IAttestationCenter.sol";

contract DistributeRewards is Script {
    function run() external {
        string memory rpcUrl = vm.envString("AMOY_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Set the private key and the contract address
        address ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;
        uint256 AVS_GOVERNANCE_OWNER = vm.envUint("PRIVATE_KEY_DEPLOYER");
        // address avsGovernanceMultisigOwner = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;

        // Start the broadcast
        vm.startBroadcast(AVS_GOVERNANCE_OWNER);

        // Create an instance of the contract
        IAttestationCenter attestationCenter = IAttestationCenter(ATTESTATION_CENTER);

        // Call the requestBatchPayment function (can be called by avsGovernanceMultisigOwner only)
        attestationCenter.requestBatchPayment();

        // Stop the broadcast
        vm.stopBroadcast();
    }
}
