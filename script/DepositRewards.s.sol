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
    uint256 private constant WETH_AMOUNT_TO_REWARD = 10 ether;

    // Configuration parameters
    HelperConfig.NetworkConfig srcNetworkConfig;

    function run() public {
        // Set up single chain
        string memory srcRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();

        uint256 privateKey = vm.envUint("PRIVATE_KEY_AVS_OWNER");

        // Start broadcasting transactions from the PRIVATE_KEY_AVS_OWNER's wallet
        vm.startBroadcast(privateKey);

        IERC20(srcNetworkConfig.weth).approve(AVS_TREASURY, WETH_AMOUNT_TO_REWARD);
        IVault(AVS_TREASURY).depositERC20(srcNetworkConfig.weth, WETH_AMOUNT_TO_REWARD); // Deployer (PRIVATE_KEY_AVS_OWNER)

        vm.stopBroadcast();
    }
}
