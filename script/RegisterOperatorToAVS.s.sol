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
    /**
     * Register operator to EigenLayer
     * @param _eigenSig Signature with salt and expiry
     * @param _authToken Authentication token for operator registration
     */
    function registerOperatorToEigenLayer(
        ISignatureUtils.SignatureWithSaltAndExpiry calldata _eigenSig,
        bytes calldata _authToken
    ) external;

    function registerAsOperator(
        uint256[4] calldata _blsKey,
        address _rewardsReceiver,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature,
        BLSAuthLibrary.Signature memory _blsRegistrationSignature
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
    bytes private constant OPERATOR_BLS_SIGNATURE =
        hex"40c359474671089ec50e24ef77c5d2bfd4aa437281a05b757d27a97488db0fe1680b55579c0a10778a9297c9cd06b91ea6c996f959807dc80a97ae7783b6f1291c";
    bytes32 private constant SIGNATURE_SALT = 0x302e323538303436313537353433333533370000000000000000000000000000;
    uint256 private constant SIGNATURE_EXPIRY =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    bytes private authToken;

    // Configuration parameters for registerAsOperator
    uint256[4] private BLS_KEY = [
        0x028d2a9b19701616bf6de5f972a98d7c4531b239fe8680a7501fa5e8a13bd3af,
        0x15bf8b9bbb3b94f75020a37d001a7ebbf00de1b6ec267228627db43586927a43,
        0x0a227c2fd9364837bf9b77260463cd06c377c2bbe55771506515c903fbe6b2ec,
        0x08cd0346cab1db2361ff67ce0156bfcbd81f850fe5938ac65c38759328393ff2
    ];
    BLSAuthLibrary.Signature private BLS_REGISTRATION_SIGNATURE = BLSAuthLibrary.Signature({
        signature: [
            0x215ed012ebe5d5ce1e1b66484d95af0e9e8c01fb29f346ff0337563a60b3ad94,
            0x0140c4e1153dc5f1564eb99a1d85b4e023386dc228e45ed87b76016473c278f5
        ]
    });

    function run() public {
        // Set up source chain
        string memory srcRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();

        uint256 privateKey = vm.envUint("PRIVATE_KEY_ATTESTER1");

        registerToEigenLayer(privateKey);
        registerAsOperator(privateKey);
    }

    function registerToEigenLayer(uint256 privateKey) public {
        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast(privateKey);

        console.log("Registering operator on EigenLayer via Othentic AVS Governance...");

        // Create the SignatureWithSaltAndExpiry struct
        ISignatureUtils.SignatureWithSaltAndExpiry memory eigenSig = ISignatureUtils.SignatureWithSaltAndExpiry({
            signature: OPERATOR_BLS_SIGNATURE,
            salt: SIGNATURE_SALT,
            expiry: SIGNATURE_EXPIRY
        });

        // Call the registration function with the struct and authToken as separate parameters
        IOthenticAVSGovernance(AVS_GOVERNANCE_ADDRESS).registerOperatorToEigenLayer(eigenSig, authToken);

        vm.stopBroadcast();
        console.log("Operator registration to EigenLayer completed successfully!");
    }

    function registerAsOperator(uint256 privateKey) public {
        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast(privateKey);

        console.log("Registering as operator on Othentic AVS...");

        // Create the SignatureWithSaltAndExpiry struct for BLS registration
        ISignatureUtils.SignatureWithSaltAndExpiry memory blsRegistrationSig = ISignatureUtils
            .SignatureWithSaltAndExpiry({signature: OPERATOR_BLS_SIGNATURE, salt: SIGNATURE_SALT, expiry: SIGNATURE_EXPIRY});

        // Get rewards receiver address from the private key
        address rewardsReceiver = vm.addr(privateKey);

        // Call the registerAsOperator function
        IOthenticAVSGovernance(AVS_GOVERNANCE_ADDRESS).registerAsOperator(
            BLS_KEY, rewardsReceiver, blsRegistrationSig, BLS_REGISTRATION_SIGNATURE
        );

        vm.stopBroadcast();
        console.log("Operator registration to Othentic AVS completed successfully!");
    }
}
