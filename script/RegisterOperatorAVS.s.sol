// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ISignatureUtils} from
    "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

struct Signature {
    uint256[2] signature;
}

// EigenLayer interfaces
interface IELDelegationManager {
    function registerAsOperator(address initDelegationApprover, uint32 allocationDelay, string calldata metadataURI)
        external;
}

interface ILiquidStakedEther {
    function approve(address spender, uint256 value) external;
    function submit(address _referral) external payable;
}

interface IStrategyManager {
    function depositIntoStrategy(address strategy, address token, uint256 amount) external;
}

// AVS Governance interface
interface IAVSGovernance {
    function registerAsOperator(
        uint256[4] calldata _blsKey,
        address _rewardsReceiver,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature,
        Signature calldata _blsRegistrationSignature
    ) external;
}

contract RegisterOperatorScript is Script {
    // Holesky addresses
    address private constant EIGEN_DELEGATION_MANAGER = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address private constant STAKED_ETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address private constant LIDO_REFERRAL_ADDRESS = 0x11d00000000000000000000000000000000011d0;
    address private constant EIGEN_STRATEGY_MANAGER = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    address private constant ST_ETH_STRATEGY = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
    address private constant AVS_GOVERNANCE_ADDRESS = 0xD23c43e9742be53029A0964C10c28EE3203420D1;
    address private constant ZERO_ADDRESS = address(0);

    // Configurable parameters
    string private metadataURI;
    uint256 private ethAmountToStake;
    uint256[4] private blsKey;
    address private rewardsReceiver;
    ISignatureUtils.SignatureWithSaltAndExpiry private operatorSignature;
    Signature private blsRegistrationSignature;

    function setUp() public {
        // Load parameters from environment variables or config file
        metadataURI = vm.envString("OPERATOR_METADATA_URI");
        ethAmountToStake = vm.envUint("ETH_AMOUNT_TO_STAKE");

        // Load BLS key
        string memory blsKeyStr = vm.envString("BLS_PUBLIC_KEY");
        (blsKey[0], blsKey[1], blsKey[2], blsKey[3]) = parseBLSKey(blsKeyStr);

        // Set rewards receiver (usually the operator's address)
        rewardsReceiver = vm.envAddress("REWARDS_RECEIVER");

        // Load signature components - these would typically be generated offline
        // using the appropriate signing libraries for EigenLayer
        operatorSignature = loadOperatorSignature();
        blsRegistrationSignature = loadBLSRegistrationSignature();
    }

    function run() public {
        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast();

        // Step 1: Register as an operator on EigenLayer
        console.log("Registering as an operator on EigenLayer...");
        IELDelegationManager(EIGEN_DELEGATION_MANAGER).registerAsOperator(ZERO_ADDRESS, 0, metadataURI);

        // Step 2: Convert ETH to stETH
        console.log("Converting ETH to stETH...");
        ILiquidStakedEther(STAKED_ETH).submit{value: ethAmountToStake}(LIDO_REFERRAL_ADDRESS);

        // Step 3: Approve and deposit stETH into strategy
        console.log("Depositing stETH into EigenLayer strategy...");
        ILiquidStakedEther(STAKED_ETH).approve(EIGEN_STRATEGY_MANAGER, ethAmountToStake);
        IStrategyManager(EIGEN_STRATEGY_MANAGER).depositIntoStrategy(ST_ETH_STRATEGY, STAKED_ETH, ethAmountToStake);

        // Step 4: Register the operator to the AVS
        console.log("Registering operator on Othentic AVS...");
        IAVSGovernance(AVS_GOVERNANCE_ADDRESS).registerAsOperator(
            blsKey, rewardsReceiver, operatorSignature, blsRegistrationSignature
        );

        vm.stopBroadcast();
        console.log("Operator registration completed successfully!");
    }

    // Helper functions to parse inputs

    function parseBLSKey(string memory blsKeyStr) internal pure returns (uint256, uint256, uint256, uint256) {
        // In a real implementation, you would parse the BLS key from a string
        // For simplicity, this is a placeholder
        // You would implement the actual parsing logic based on your BLS key format

        // For demo purposes, returning placeholder values
        return (0, 0, 0, 0);
    }

    function loadOperatorSignature() internal view returns (ISignatureUtils.SignatureWithSaltAndExpiry memory) {
        // Load EigenLayer signature components from env variables
        bytes memory signature = vm.envBytes("OPERATOR_SIGNATURE");
        bytes32 salt = vm.envBytes32("SIGNATURE_SALT");
        uint256 expiry = vm.envUint("SIGNATURE_EXPIRY");

        return ISignatureUtils.SignatureWithSaltAndExpiry({signature: signature, salt: salt, expiry: expiry});
    }

    function loadBLSRegistrationSignature() internal view returns (Signature memory) {
        // Load BLS signature components from env variables
        string memory sigStr = vm.envString("BLS_SIGNATURE");

        // Parse the signature string into the expected format
        // This is a simplified example - actual implementation would depend on your signature format
        uint256[2] memory sig;
        sig[0] = vm.envUint("BLS_SIGNATURE_PART_1");
        sig[1] = vm.envUint("BLS_SIGNATURE_PART_2");

        return Signature({signature: sig});
    }
}
