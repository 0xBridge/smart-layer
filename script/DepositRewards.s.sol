// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

interface IVault {
    function depositERC20(address token, uint256 amountWithFee) external;
}

contract DepositRewardsScript is Script {
    address private AVS_TREASURY = vm.envAddress("L1_AVS_TREASURY");
    address private ATTESTATION_CENTER = vm.envAddress("ATTESTATION_CENTER_ADDRESS");
    address private ERC20_TO_BE_REWARDED;
    uint256 private ERC20_AMOUNT_TO_REWARD;

    // Configuration parameters
    HelperConfig.NetworkConfig srcNetworkConfig;

    function run() public {
        // Set up single chain
        string memory srcRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();

        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        ERC20_TO_BE_REWARDED = ERC20_TO_BE_REWARDED == address(0) ? srcNetworkConfig.weth : ERC20_TO_BE_REWARDED;
        ERC20_AMOUNT_TO_REWARD =
            ERC20_AMOUNT_TO_REWARD == 0 ? _calculateERC20AmountToBeRewarded() : ERC20_AMOUNT_TO_REWARD; // 1 WETH
        IERC20(ERC20_TO_BE_REWARDED).approve(AVS_TREASURY, ERC20_AMOUNT_TO_REWARD);
        IVault(AVS_TREASURY).depositERC20(ERC20_TO_BE_REWARDED, ERC20_AMOUNT_TO_REWARD);

        vm.stopBroadcast();
    }

    function _calculateERC20AmountToBeRewarded() internal returns (uint256) {
        // TODO: Implement the logic to calculate the amount of ERC20 to be rewarded
    }
}
