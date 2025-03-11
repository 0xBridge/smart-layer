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
    bytes32 internal constant BLOCK_HASH = 0x00000000d5e6c2af3f74d53bac835137c3414bcb654521d813a372eac0ce4155; // Block hash
    bytes32 internal constant BTC_TXN_HASH = 0x63d2189bacdd8f610bce19e493827880bb839019727728ec8f6031b90e2e9e2e; // BTC transaction hash

    // PSBT data represents the Bitcoin transaction
    bytes internal constant PSBT_DATA =
        hex"0200000000010172a9903e9c75393c69cd155f4842796b3c52454dad15d83e627749de6c78a7780100000000ffffffff041027000000000000160014b7a229b0c1c10c214d1b19d1263b6797dae3e978e80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a30001471cf07d9c0d8e4bbb5019ccc60437c53fc51e6de00080000000000002710000400009ce100080000000000000000a82a000000000000160014d5a028b62114136a63ebcfacf94e18536b90a1210247304402206d80652d1cc1c6c4b2fe08ae3bdfa2c97121017b07826f7db0a232292c1d74020220579da941457f0d40b93443cf1a223693c59c352a188430f76682d89442918b6d0121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";

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
        bytes32[] memory proof = new bytes32[](11);
        proof[0] = 0x20753e310cc491f86ca2f87af292aaceddb7e12773c965c5ce56fb2610b3a85b;
        proof[1] = 0xc91fdeaeec9f532dea4e0d0f175eacad01aa6df5f79fd12eb0cf60a0b45403cc;
        proof[2] = 0x25f944d1fbc29ada8b2fb1e3b844d70f4faefc6e3b437c6357a79c70ecd2ee2f;
        proof[3] = 0x7610680b480d5f26076d4e525c1ab470a4e8383dd2f7423f340f4c18aa9f8321;
        proof[4] = 0xdc5eb091c00510e7df8d46e41947d76fbbd55f814ca4c599238ff5e3ce4d5324;
        proof[5] = 0xe40462e9e50b441bdfa196d11d7464ed2ebe06f10535aa3b18e23cff7bf3c824;
        proof[6] = 0x29c246c61959e3acfbef45f8f6cadedc1c02081cfa2ae7a554f8dae97e025dfd;
        proof[7] = 0x7c53eb3c41a613e70581f8bf478d412904db531281c5a0873af8c2d2d1084d74;
        proof[8] = 0x2cdc8b9432085da444d4f0ce3a7977987f709ed541b05c75c4f30800e0af5597;
        proof[9] = 0x8c1f53dd9d4bc6f03f5af029497e87887f35564be5cbda806dfc98b828d633f9;
        proof[10] = 0x94badf85663bd5b31bf89ea9ffef3a83a4e35665fbc837ee2d03447a53e729ff;
        uint256 index = 131;

        // Prepare LayerZero options
        bytes memory optionType = abi.encodePacked(uint16(3));
        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(optionType, 200000, 0);
        console.logBytes(options);

        // Calculate required messaging fee
        (uint256 nativeFee,) = _coordinator.quote(BTC_TXN_HASH, PSBT_DATA, false);
        console.log("Required native fee:", nativeFee);

        // Send the message
        _coordinator.sendMessage{value: nativeFee * 2}(BTC_TXN_HASH);

        vm.stopBroadcast();
    }
}
