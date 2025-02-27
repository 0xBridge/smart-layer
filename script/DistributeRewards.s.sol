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
    address internal constant ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;

    /**
     * @notice Main execution function
     * @dev Calls the requestBatchPayment function on the AttestationCenter
     */
    function run() external {
        string memory rpcUrl = vm.envString("AMOY_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Set the private key for the AVS governance owner
        uint256 avsGovernanceOwnerKey = vm.envUint("PRIVATE_KEY_DEPLOYER");

        // Start the broadcast
        vm.startBroadcast(avsGovernanceOwnerKey);

        // Create an instance of the contract
        IAttestationCenter attestationCenter = IAttestationCenter(ATTESTATION_CENTER);

        // Call the requestBatchPayment function (can be called by avsGovernanceMultisigOwner only)
        attestationCenter.requestBatchPayment();

        // Stop the broadcast
        vm.stopBroadcast();
    }
}
