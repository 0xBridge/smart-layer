// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {IAttestationCenter} from "../src/interfaces/IAttestationCenter.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";

/**
 * @title CreateTask
 * @notice Script to create tasks on the TaskManager
 */
contract CreateTask is Script {
    // Constants
    address internal constant TASK_MANAGER = 0x193E4337379B597C7842bdc17bF1Cb2782b27762;

    // Bitcoin SPV Testnet constants (from test file)
    bytes32 internal constant MINT_BLOCK_HASH = 0x00000000ad4e9e95f8c6459a406accc761f78b2092b931a6d954f545dcc14e0d;
    bytes32 internal constant MINT_BTC_TXN_HASH = 0xb0a97d6e5c2844480b0b6b025b68dee5f70d16938f31f2cc1854814605c2a4f9;
    bytes internal constant MINT_RAW_TXN =
        hex"020000000001019525b5171e07c34b4866e2a220dc81456802b259e9aa3a43bcca76ca08b876aa0000000000ffffffff041027000000000000225120b2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33be80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144e56a8e3757f167378b38269e1ca0e1a1f124c9e00080000000000002710000400009ca60008000000000000007bde03000000000000160014d5a028b62114136a63ebcfacf94e18536b90a12102483045022100fc0b6566f5f802fcff22a9105a0408c6228814887301c464d0e8cc1cb61daa9d022068774e9d4a023113f7c450032220d58967eeff232dbf322915a157e2386138fb0121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";

    // AVS Data (from test file)
    bytes32 internal constant TAPROOT_ADDRESS = 0xb2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33b;
    bytes32 internal constant NETWORK_KEY = 0xb7a229b0c1c10c214d1b19d1263b6797dae3e978000000000000000000000000;

    /**
     * @notice Main execution function
     * @dev Creates a task on the task manager
     */
    function run() external {
        string memory rpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Set up private keys and derive addresses
        uint256 privateKeyGenerator = vm.envUint("GENERATOR_PRIVATE_KEY");

        // Create the TaskManager contract instance
        TaskManager taskManager = TaskManager(payable(TASK_MANAGER));

        // Set up Merkle proof (from test file)
        bytes32[] memory proof = new bytes32[](8);
        proof[0] = 0xcb87dfbc1b918ba4cf95717ab00096d7e40e4b8fe23504a99f73ad1228fed850;
        proof[1] = 0xc103aecc30a5983383163a26eb9c3fb71da376de42a4b22174df27e9b23c7f26;
        proof[2] = 0xfb049402176a0da0fbdc4180abe06954ac8d7003e83c64dbb20b316609ff7ac0;
        proof[3] = 0x8d7487baf49a82a569c5541d082831ff51a1218044f23250618fc0b0a30ccbf3;
        proof[4] = 0x8b529655f91a84c9e88b9bbcd38ce01409cb030527dcaf356da063fe503badf5;
        proof[5] = 0x23289413d58bf5e1737d41c3be17cc8dde25907e5948b86da16d024d05f04533;
        proof[6] = 0x4692c9ca97522b10e68fdf6bb5f2175f6e4dcf4845c41daa462c48eb677568ea;
        proof[7] = 0x2b5da79464a83356da2dcbae23e47fd1b68f0a29f9e562c7c89dc1899881df6e;
        uint256 index = 24;

        address[] memory operators = new address[](3);
        operators[0] = 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE;
        operators[1] = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;
        operators[2] = 0xEC1Fa15145c4d27F7e8645F2F68c0E0303AE5690;

        // Start the broadcast as task generator
        vm.startBroadcast(privateKeyGenerator);

        // Create a task on the TaskManager
        address taskPerformer = vm.addr(privateKeyGenerator);
        bytes memory data = abi.encode(
            true, // txnType
            MINT_BTC_TXN_HASH, // Bitcoin txn hash / PSBT for burn by the user
            MINT_BTC_TXN_HASH); // Actual Bitcoin mint txn hash
            
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "Random string",
            data: data,
            taskPerformer: taskPerformer,
            taskDefinitionId: 0
        });

        HomeChainCoordinator.NewTaskParams memory params = HomeChainCoordinator.NewTaskParams({
            isMintTxn: true,
            blockHash: MINT_BLOCK_HASH,
            btcTxnHash: MINT_BTC_TXN_HASH,
            proof: proof,
            index: index,
            rawTxn: MINT_RAW_TXN,
            taprootAddress: TAPROOT_ADDRESS,
            networkKey: NETWORK_KEY,
            operators: operators
        });

        // Create new task on the TaskManager
        taskManager.createNewTask(
            taskInfo,
            params
        );

        // Stop the broadcast
        vm.stopBroadcast();
    }
}
