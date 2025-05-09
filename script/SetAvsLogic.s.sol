// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {IAttestationCenter} from "../src/interfaces/IAttestationCenter.sol";

/**
 * @title SetAvsLogic
 * @notice Script to set the AVS logic contract on the AttestationCenter
 * @dev Can only be called by the AVS governance owner
 */
contract SetAvsLogicScript is Script {
    // Constants
    address internal constant ATTESTATION_CENTER = 0xEA40f823f46CB372Cf58C184a9Ee7ECCF0200f07;
    address internal constant TASK_MANAGER = 0x5f5bdbbe7df9123b9E825157866F5Ac4B4b3Cd1E;

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
        attestationCenter.setAvsLogic(TASK_MANAGER);

        // Stop the broadcast
        vm.stopBroadcast();
    }
}
