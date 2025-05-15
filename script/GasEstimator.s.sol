// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HomeChainCoordinator} from "../src/HomeChainCoordinator.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {HelperConfig} from "./HelperConfig.s.sol"; // Adjust path if necessary
import {BitcoinTxnParser} from "../src/libraries/BitcoinTxnParser.sol"; // For constants if needed
import {BitcoinUtils} from "../src/libraries/BitcoinUtils.sol"; // For constants if needed
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";


contract GasEstimator is OApp {

    bytes internal constant OPTIONS = hex"00030100110100000000000000000000000000030D40";

    constructor(address endpoint_) OApp(endpoint_, msg.sender) {
        // Initialize the contract with the endpoint and owner
    }

    function setPeer(uint32 _dstEid, bytes32 _peer) public override {
        super.setPeer(_dstEid, _peer);
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal virtual override {
        // Handle the incoming LayerZero message
    }

    function quote(uint32 chainEid, address receiverAddress, bytes32 btcTxnHash, uint256 lockedAmount, uint256 nativeTokenAmount)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        bytes memory payload =
            abi.encode(receiverAddress, btcTxnHash, lockedAmount, nativeTokenAmount);
        MessagingFee memory fee = _quote(chainEid, payload, OPTIONS, false);
        return (fee.nativeFee, fee.lzTokenFee);
    }
}

contract GasEstimatorScript is Script {

    // Core = 40153, BSC = 40102, Sepolia = 40161 (for Testnets)
    // Core = 30153, BSC = 30102, Ethereum = 30101 (for Mainnets)
    uint32 constant DST_CHAIN_EID = 40161; // Replace with actual destination chain EID
    address RECEIVER_ADDRESS = 0xEE35AB43127933562c65A7942cbf1ccAac4BE86F; // Replace with actual receiver address
    bytes32 ADDRESS_HASH = bytes32(uint256(uint160(RECEIVER_ADDRESS)));

    function run() external {
        string memory srcRpcUrl = vm.envString("FUJI_TESTNET_RPC_URL");
        vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory srcNetworkConfig = srcConfig.getConfig();

        vm.startBroadcast();
        GasEstimator gasEstimator = new GasEstimator(srcNetworkConfig.endpoint);
        console.log("Gas Estimator deployed to:", address(gasEstimator));
        gasEstimator.setPeer(DST_CHAIN_EID, ADDRESS_HASH);
        (uint256 nativeGasRequired,) = gasEstimator.quote(
            DST_CHAIN_EID,
            RECEIVER_ADDRESS,
            ADDRESS_HASH,
            100000000,
            100000001
        );
        console.log("Native Gas:", nativeGasRequired);
        vm.stopBroadcast();
    }
}
