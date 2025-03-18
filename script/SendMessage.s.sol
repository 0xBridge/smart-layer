// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title SendMessageScript
 * @notice Script to send a cross-chain message via the HomeChainCoordinator
 * @dev Uses real Bitcoin block data for the proof
 */
contract SendMessageScript is Script {
    // Contract instance
    HomeChainCoordinator internal _coordinator;

    // Constants - to be updated for each deployment
    address internal constant COORDINATOR_ADDRESS = 0xEE35AB43127933562c65A7942cbf1ccAac4BE86F; // HomeChainCoordinator contract address on Amoy
    bytes32 internal constant BLOCK_HASH = 0x000000000000000389f10a859bdd004ad55184d3b651b17019f9ec3f3e9b1eab; // Block hash
    bytes32 internal constant BTC_TXN_HASH = 0x135dc957a39da6d292c62071b6d8e51a6b8b730cce923074163d7c879c69f9fb; // BTC transaction hash

    // PSBT data represents the Bitcoin transaction
    bytes internal constant PSBT_DATA =
        hex"02000000000102137d512d277b25677a4a7f522581d4d6e47ee85fd3b9353fdc7d17a05ae2e7bd0300000000ffffffff9e504ef8a97d1c29c8df3db5e79fdc2dc362d2d770c66e234a849b915a449e1d0300000000ffffffff048813000000000000225120b2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33bf40100000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144e56a8e3757f167378b38269e1ca0e1a1f124c9e00080000000000001388000400009cd90008000000000000007b3703000000000000160014d5a028b62114136a63ebcfacf94e18536b90a12102473044022008e4d0e467c608cd8cf936418679aaec3d89da309c08c6a8b6fa969c8215d07802206907b7fd7c2a22468b2c676a293808d1f911c45fb078be4089917d3832644a9b0121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250602473044022029244e5bb4cbedb64095a19a78b47ebb7befc0d7dc3a45373a9d01ce3b713c6b022064cab458ddfe4f90296da56f1c5701057523ec2bae18c1de4879f1a7e8a8dbd90121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";

    /**
     * @notice Setup function for the script
     * @dev Initializes the coordinator contract instance
     */
    function setUp() public {
        _coordinator = HomeChainCoordinator(payable(COORDINATOR_ADDRESS));
    }

    /**
     * @notice Main execution function
     * @dev Sends a message with Merkle proof for a Bitcoin transaction
     */
    function run() public {
        uint256 aggregatorPrivateKey = vm.envUint("AGGREGATOR_PRIVATE_KEY");

        string memory srcRpcUrl = vm.envString("AMOY_RPC_URL");
        vm.createSelectFork(srcRpcUrl);

        vm.startBroadcast(aggregatorPrivateKey);

        // Prepare Merkle proof
        bytes32[] memory proof = new bytes32[](12);
        proof[0] = 0xf4db6b54e878a9d07765a5c0dd8aaa51d6cad48e5ef06a26d34e6a6eb04f624b;
        proof[1] = 0xb6ac985bc099adaaf04c24cf8c39d3686d1038ed3b6e1ef0481471a831b90b19;
        proof[2] = 0xad18fa03e483652376b7068f7d3e0099d35a2577bdc96d546f3bb1708d84459b;
        proof[3] = 0x66a7cdd9724504fe2361625b2d8a1592c1c519bc6501ead94d0600f78ba95257;
        proof[4] = 0xc32f6e36ea3edb57ff8d9b5abfb03bc4ae456c1d0a9d7f572aca464065cd63d5;
        proof[5] = 0x2780f8e4b4b908ff788d39ece801f1acd99543aa0f29a88aa175930d76f69932;
        proof[6] = 0xf62e67d33f5b2ffc195cf4dc2857c8571efd3a345d2f98dc5e60a1cc23fbf34d;
        proof[7] = 0x652cfcfe29525c948a323a34399f78f2c3a8f6be346b68fc4dc2bcb6ecf5355f;
        proof[8] = 0x5a9118fc794bdf87c435ea4ccb3341d767e9b3a82188d23e586e5ad21877de05;
        proof[9] = 0xeb50343912b5ec8fd656afb78d35f5c71ca2c8a705f57c8b34644d66a030bc23;
        proof[10] = 0xadf2a22529194af8c63aff7a3166751bfff386534dae7f743c10d00a85af6585;
        proof[11] = 0xfdf40c18f845da81af5e5a90bb0f22cf7ee9a4a4e7ed8d574f90a09b7260bc03;
        uint256 index = 355;

        // Prepare LayerZero options
        bytes memory optionType = abi.encodePacked(uint16(3));
        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(optionType, 200000, 0);
        console.logBytes(options);

        // Calculate required messaging fee
        (uint256 nativeFee,) = _coordinator.quote(BTC_TXN_HASH, PSBT_DATA, options, false);
        console.log("Required native fee:", nativeFee);

        // Send the message
        _coordinator.sendMessage{value: nativeFee}(BLOCK_HASH, BTC_TXN_HASH, proof, index, PSBT_DATA, options);

        vm.stopBroadcast();
    }
}
