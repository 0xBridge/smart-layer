// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {IAttestationCenter} from "../src/interfaces/IAttestationCenter.sol";

/**
 * @title DistributeRewards
 * @notice Script to distribute rewards through the AttestationCenter
 * @dev Can only be called by the AVS governance owner
 */
contract DistributeRewards is Script {
    // Constants
    address internal constant ATTESTATION_CENTER = 0xf8858A9d9794C1A73272f21a7dB84471F491797F;

    // Operators to reward to
    uint256 internal constant FROM_OPERATOR_ID = 3;
    uint256 internal constant TO_OPERATOR_ID = 4;

    /**
     * @notice Main execution function
     * @dev Calls the requestBatchPayment function on the AttestationCenter
     */
    function run() external {
        string memory rpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Set the private key for the AVS governance owner
        uint256 avsGovernanceOwnerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Start the broadcast
        vm.startBroadcast(avsGovernanceOwnerKey);

        // Create an instance of the contract
        IAttestationCenter attestationCenter = IAttestationCenter(ATTESTATION_CENTER);

        // Call the requestBatchPayment function (can be called by avsGovernanceMultisigOwner only)
        attestationCenter.requestBatchPayment(FROM_OPERATOR_ID, TO_OPERATOR_ID);

        // Stop the broadcast
        vm.stopBroadcast();
    }
}
