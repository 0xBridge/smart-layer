// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

// Deployed on Holesky at 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3
interface IAttestationCenter {
    // Only AVS Governance Multisig address can call this function - Disburses funds to the respective operators
    function requestBatchPayment() external;

    // Alternatively, Operators can claim rewards using the withdrawRewards function on L2 AVS treasury contract(deployed on Amoy at 0xa446A9fEd7527BbdbF16305fA2b04Ab4a2F4E386)
}

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
