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
    bytes32 internal constant BLOCK_HASH = 0x000000000000a20dbeee6d8c5f448e71608e62972c1ff7dd53c567a2df33ff53; // Block hash #72016
    bytes32 internal constant BTC_TXN_HASH = 0x63d2189bacdd8f610bce19e493827880bb839019727728ec8f6031b90e2e9e2e; // BTC transaction hash

    // PSBT data represents the Bitcoin transaction
    bytes internal constant RAW_TXN =
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

        // Prepare Merkle proof (This would be needed to store the block data in the SPV contract)
        bytes32[] memory proof = new bytes32[](11);
        proof[0] = 0x58e3e27ef80ea9af7cbf6c68414a1a30c4936442fbb78d954763a385b2cf34b4;
        proof[1] = 0x9c60aac47f15333f997af21ef95f91fc170b2cf74550d5537bc0f8b7b268859f;
        proof[2] = 0xfd072d502d65a9621a9cc67bba66d0ebeb8072c38e076cd321201ebc5d0fcf44;
        proof[3] = 0xc7ed53c752b40989e0b28b9a466b7e4d247a3c8c08aa06ff09faddcc89fc1f5c;
        proof[4] = 0xbca34a332518e157bf2bc61d07b9f79a5718306ef9770c9e31d9671c64e0e796;
        proof[5] = 0xb9af329f68773536fea223d8b0733bdce478b19eef448f2c9e777ad0e93c556e;
        proof[6] = 0x745e6898ccd4b8bed3bfe0972d2054ce711696250c6007a4958559dec729ff3e;
        proof[7] = 0xbce49ee30b6ac4361edee0fb70d13d73b4d368080d957747b9e3d76a6ba23915;
        proof[8] = 0x68a804445edf53b793135300e80f45b0160fa4f9dcf1ca6bcf7313ec6b3e4cdd;
        proof[9] = 0x75a385f7ecc1a6c9571b60428cb2f91c0eaf2f88d6396a071cc50dca096d8cb1;
        proof[10] = 0xce78d0c5bcc327d656cab0e8bca278b21d6f3f4438cd57d36b31640efb834e15;
        uint256 index = 132;

        // Calculate required messaging fee
        (uint256 nativeFee,) = _coordinator.quote(BTC_TXN_HASH, RAW_TXN, false);
        console.log("Required native fee:", nativeFee);

        // Send the message
        _coordinator.sendMessage{value: nativeFee * 2}(BTC_TXN_HASH);

        vm.stopBroadcast();
    }
}
