// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ISignatureUtils} from
    "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

interface IEigenLayerDelegationManager {
    function registerAsOperator(address initDelegationApprover, uint32 allocationDelay, string calldata metadataURI)
        external;
}

contract RegisterOperatorOnEigenLayerScript is Script {
    // Contract address from the provided transaction
    address private EIGEN_DELEGATION_MANAGER = 0xA44151489861Fe9e3055d95adC98FbD462B948e7; // TODO: Get from config

    // Configuration parameters
    address private constant INIT_DELEGATION_APPROVER = address(0);
    uint32 private constant ALLOCATION_DELAY = 0;
    // NOTE: The below url stores name, website, description, logo, and twitter metadata of the operator
    string private constant metadataURI =
        "https://othentic.mypinata.cloud/ipfs/QmbfNEJrEE2X6XeHeST5TFrwRyUXDCDzqfknJe7fG1mjgc/operator.json";

    function run() public {
        // Set up single chain
        string memory rpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        uint256 privateKey = vm.envUint("PRIVATE_KEY_ATTESTER1");

        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast(privateKey);

        console.log("Registering operator on EigenLayer");

        // Call the registration function with the struct and authToken as separate parameters
        IEigenLayerDelegationManager(EIGEN_DELEGATION_MANAGER).registerAsOperator(
            INIT_DELEGATION_APPROVER, ALLOCATION_DELAY, metadataURI
        );

        vm.stopBroadcast();
        console.log("Operator registration to EigenLayer completed successfully!");
    }
}
