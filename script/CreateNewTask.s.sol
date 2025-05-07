// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title CreateNewTaskScript
 */
contract CreateNewTaskScript is Script {
    // Contract instance
    TaskManager internal taskManager;

    // Constants - to be updated for each deployment
    address internal constant TM_ADDRESS = 0x193E4337379B597C7842bdc17bF1Cb2782b27762; // HomeChainCoordinator contract address on Amoy
   
    /**
     * @notice Setup function for the script
     */
    function setUp() public {
        taskManager = TaskManager(payable(TM_ADDRESS));
    }

    /**
     * @notice Main execution function
     * @dev Executes createNewTask on the TaskManager contract
     */
    function run() public {
        uint256 generatorPrivateKey = vm.envUint("GENERATOR_PRIVATE_KEY");

        string memory srcRpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(srcRpcUrl);

        vm.startBroadcast(generatorPrivateKey);

         // Create a new task
        bytes32 blockHash = 0x00000000000000050cc414d720b54db5cb87402fff18f50bd1458f5b295553de;
        bytes32 btcTxnHash = 0x838b8183e2b96d9f77bc7f8ff2ef7bdda352fa392820c72cd0a0a391bfa36773;
        bytes memory rawTxn = hex"02000000000101547e26305d69a8f4d97d3dd848a6fe97c37c2ba70144f54efc9acac9baea5b060000000000ffffffff04102700000000000022512007980efd70d3620584be0ab5123c13593488829982651b1fa5483809749a7f7ae80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144838b106fce9647bdf1e7877bf73ce8b0bad5f9700080000000000002710000400009ca60008000000000001869fc92e000000000000160014d6a279dc882b830c5562b49e3e25bf3c5767ab730247304402202a3334b57430cb43abfbf9e8ef5639e7b6242d4d73817ceda1354ff8cb9e52a002203a84cf9b2515f7d56aec96fb30f0233c1ab16c6f54caf20e35f359f0f889660e01210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb00000000";
        bytes32 taprootAddress = 0x07980efd70d3620584be0ab5123c13593488829982651b1fa5483809749a7f7a;
        bytes32 networkKey = 0x07980efd70d3620584be0ab5123c13593488829982651b1fa5483809749a7f7a;
        bytes32[] memory proof = new bytes32[](0);
        address[] memory operators = new address[](1);
        operators[0] = 0x193E4337379B597C7842bdc17bF1Cb2782b27762;
        taskManager.createNewTask(
            true, blockHash, btcTxnHash, proof, 0, rawTxn, taprootAddress, networkKey, operators
        );

        vm.stopBroadcast();
    }
}
