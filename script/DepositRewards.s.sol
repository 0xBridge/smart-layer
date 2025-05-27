// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IAttestationCenter} from "../src/interfaces/IAttestationCenter.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

interface IVault {
    function depositERC20(address token, uint256 amountWithFee) external;
}

contract DepositRewardsScript is Script {
    address private AVS_TREASURY = vm.envAddress("L1_AVS_TREASURY");
    address private ATTESTATION_CENTER = vm.envAddress("ATTESTATION_CENTER_ADDRESS");
    address private erc20ToBeRewarded;
    uint256 private erc20AmountToBeRewarded;

    // Configuration parameters
    HelperConfig.NetworkConfig srcNetworkConfig;
    HelperConfig.NetworkConfig destNetworkConfig;

    function run() public {
        _calculateERC20AmountToBeRewarded();

        // Set up source chain fork
        string memory srcRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();

        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        erc20ToBeRewarded = erc20ToBeRewarded == address(0) ? srcNetworkConfig.weth : erc20ToBeRewarded;
        console.log("Amount to be rewarded: ", erc20AmountToBeRewarded);
        // TODO: You can also check if the L1_AVS_TREASURY on L1 already has the required erc20AmountToBeRewarded and skip the deposit if it does
        IERC20(erc20ToBeRewarded).approve(AVS_TREASURY, erc20AmountToBeRewarded);
        IVault(AVS_TREASURY).depositERC20(erc20ToBeRewarded, erc20AmountToBeRewarded);

        vm.stopBroadcast();
    }

    function _calculateERC20AmountToBeRewarded() internal returns (uint256 amountToBeRewarded) {
        // Set up destination chain fork
        string memory destRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(destRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        destNetworkConfig = destConfig.getConfig();

        uint256 numOfActiveOperators = IAttestationCenter(ATTESTATION_CENTER).numOfActiveOperators();
        for (uint256 i = 1; i <= numOfActiveOperators; i++) {
            IAttestationCenter.PaymentDetails memory paymentDetail =
                IAttestationCenter(ATTESTATION_CENTER).getOperatorPaymentDetail(i);
            if (paymentDetail.feeToClaim > 0) {
                amountToBeRewarded += paymentDetail.feeToClaim;
            }
        }
        erc20AmountToBeRewarded = erc20AmountToBeRewarded == 0 ? amountToBeRewarded : erc20AmountToBeRewarded;
    }
}
