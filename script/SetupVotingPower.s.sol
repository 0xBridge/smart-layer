// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";

interface ILiquidStakedEther {
    function approve(address spender, uint256 value) external;
    function submit(address _referral) external payable;
}

interface IStrategyManager {
    function depositIntoStrategy(address strategy, address token, uint256 amount) external;
}

contract SetupVotingPowerScript is Script {
    // Holesky addresses
    address private constant STAKED_ETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034; // Needs to be replaced with the WETH address
    address private constant LIDO_REFERRAL_ADDRESS = 0x11d00000000000000000000000000000000011d0;
    address private constant EIGEN_STRATEGY_MANAGER = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    address private constant ST_ETH_STRATEGY = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3; // Needs to be replaced with the WETH strategy address

    // Configurable parameters
    uint256 private constant ETH_AMOUNT_TO_STAKE = 10 ether; // NOTE: This should be changed to the desired amount

    function run() public {
        // Set up single chain
        string memory rpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        uint256 privateKey = vm.envUint("PRIVATE_KEY_ATTESTER5");

        // Start broadcasting transactions from the operator's wallet
        vm.startBroadcast(privateKey);

        // Step 1: Convert ETH to stETH
        console.log("Converting ETH to stETH...");
        ILiquidStakedEther(STAKED_ETH).submit{value: ETH_AMOUNT_TO_STAKE}(LIDO_REFERRAL_ADDRESS);

        // Step 2: Approve and deposit stETH into strategy
        console.log("Depositing stETH into EigenLayer strategy...");
        ILiquidStakedEther(STAKED_ETH).approve(EIGEN_STRATEGY_MANAGER, ETH_AMOUNT_TO_STAKE);
        IStrategyManager(EIGEN_STRATEGY_MANAGER).depositIntoStrategy(ST_ETH_STRATEGY, STAKED_ETH, ETH_AMOUNT_TO_STAKE);

        vm.stopBroadcast();
    }
}
