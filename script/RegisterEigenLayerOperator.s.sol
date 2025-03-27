// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ISignatureUtils} from
    "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

// Interface for the Othentic AVS Governance contract
interface IOthenticAVSGovernance {
    function registerOperatorToEigenLayer(
        ISignatureUtils.SignatureWithSaltAndExpiry calldata _eigenSig,
        bytes calldata _authToken
    ) external;
}

contract RegisterEigenLayerOperatorScript is Script {
    // Contract address from the provided transaction
    address private AVS_GOVERNANCE_ADDRESS = vm.envAddress("AVS_GOVERNANCE_ADDRESS");

    // Configuration parameters
    bytes private signature;
    bytes32 private salt;
    uint256 private expiry;
    bytes private authToken;

    function setUp() public {
        // Load parameters from environment variables
        signature = vm.envBytes("OPERATOR_SIGNATURE");
        salt = vm.envBytes32("SIGNATURE_SALT");

        // Default to max uint256 if no expiry provided
        expiry = vm.envOr("SIGNATURE_EXPIRY", type(uint256).max);

        // Auth token (optional)
        authToken = vm.envBytes("AUTH_TOKEN");

        // If signature wasn't provided in environment, use the example from transaction
        if (signature.length == 0) {
            bytes32 r = 0x0a98ce41969102d187d2418be67fad683f26ad6fd3580ddcc51ca1735b3a9be5;
            bytes32 s = 0x31a2b80b32facd4b778e121f1dfd214d14ab8494c84d930176190571266b4fd9;
            uint8 v = 27; // 0x1b
            signature = abi.encodePacked(r, s, v);
        }

        // If salt wasn't provided, generate a random one
        if (salt == bytes32(0)) {
            salt = keccak256(abi.encodePacked(block.timestamp, msg.sender));
        }
    }

    function run() public {
        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast();

        console.log("Registering operator on EigenLayer via Othentic AVS Governance...");

        // Create the SignatureWithSaltAndExpiry struct
        ISignatureUtils.SignatureWithSaltAndExpiry memory eigenSig =
            ISignatureUtils.SignatureWithSaltAndExpiry({signature: signature, salt: salt, expiry: expiry});

        // Call the registration function with the struct and authToken as separate parameters
        IOthenticAVSGovernance(AVS_GOVERNANCE_ADDRESS).registerOperatorToEigenLayer(eigenSig, authToken);

        vm.stopBroadcast();
        console.log("Operator registration to EigenLayer completed successfully!");
    }
}
