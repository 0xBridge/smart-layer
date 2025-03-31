// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ISignatureUtils} from
    "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

interface BLSAuthLibrary {
    struct Signature {
        uint256[2] signature;
    }
}

// Interface for the Othentic AVS Governance contract
interface IOthenticAVSGovernance {
    function registerAsOperator(
        uint256[4] calldata _blsKey,
        address _rewardsReceiver,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature,
        BLSAuthLibrary.Signature memory _blsRegistrationSignature
    ) external;

    /**
     * Register operator to EigenLayer
     * @param _eigenSig Signature with salt and expiry
     * @param _authToken Authentication token for operator registration
     */
    function registerOperatorToEigenLayer(
        ISignatureUtils.SignatureWithSaltAndExpiry calldata _eigenSig,
        bytes calldata _authToken
    ) external;
}

contract RegisterOthenticOperatorScript is Script {
    // Contract address from the provided transaction
    address private AVS_GOVERNANCE_ADDRESS = vm.envAddress("AVS_GOVERNANCE_ADDRESS");

    // Enum to define the registration mode
    enum RegistrationMode {
        EigenLayer,
        OthenticAVS
    }

    RegistrationMode private mode;
    HelperConfig.NetworkConfig srcNetworkConfig;

    // Configuration parameters for registerOperatorToEigenLayer
    bytes private operatorSignature;
    bytes32 private signatureSalt;
    uint256 private signatureExpiry;
    bytes private authToken;

    // Configuration parameters for registerAsOperator
    uint256[4] private blsKey;
    address private rewardsReceiver;
    bytes32 private blsSignatureSalt;
    uint256 private blsSignatureExpiry;
    bytes private blsSignature;
    BLSAuthLibrary.Signature private blsRegistrationSignature;

    function run() public {
        // Set up source chain
        string memory srcRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();

        uint256 privateKey = vm.envUint("PRIVATE_KEY_ATTESTER1");

        registerToEigenLayer(privateKey);
    }

    function registerToEigenLayer(uint256 privateKey) public {
        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast(privateKey);

        console.log("Registering operator on EigenLayer via Othentic AVS Governance...");

        operatorSignature =
            hex"40c359474671089ec50e24ef77c5d2bfd4aa437281a05b757d27a97488db0fe1680b55579c0a10778a9297c9cd06b91ea6c996f959807dc80a97ae7783b6f1291c";
        signatureSalt = 0x302e323538303436313537353433333533370000000000000000000000000000;
        signatureExpiry = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

        // Create the SignatureWithSaltAndExpiry struct
        ISignatureUtils.SignatureWithSaltAndExpiry memory eigenSig = ISignatureUtils.SignatureWithSaltAndExpiry({
            signature: operatorSignature,
            salt: signatureSalt,
            expiry: signatureExpiry
        });

        // Call the registration function with the struct and authToken as separate parameters
        IOthenticAVSGovernance(AVS_GOVERNANCE_ADDRESS).registerOperatorToEigenLayer(eigenSig, authToken);

        vm.stopBroadcast();
        console.log("Operator registration to EigenLayer completed successfully!");
    }

    function registerAsOperator() public {
        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast();

        console.log("Registering as operator on Othentic AVS...");
        console.log("Rewards Receiver: %s", rewardsReceiver);

        // Create the SignatureWithSaltAndExpiry struct for BLS registration
        ISignatureUtils.SignatureWithSaltAndExpiry memory blsRegistrationSig = ISignatureUtils
            .SignatureWithSaltAndExpiry({signature: blsSignature, salt: blsSignatureSalt, expiry: blsSignatureExpiry});

        // Call the registerAsOperator function
        IOthenticAVSGovernance(AVS_GOVERNANCE_ADDRESS).registerAsOperator(
            blsKey, rewardsReceiver, blsRegistrationSig, blsRegistrationSignature
        );

        vm.stopBroadcast();
        console.log("Operator registration to Othentic AVS completed successfully!");
    }
}
