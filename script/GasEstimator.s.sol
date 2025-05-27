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
    bytes internal constant MINT_OPTIONS = hex"00030100110100000000000000000000000000030D40";
    bytes internal constant BURN_OPTIONS = hex"000301001101000000000000000000000000001209c4";

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

    function mintQuote(
        uint32 chainEid,
        address receiverAddress,
        bytes32 btcTxnHash,
        uint256 lockedAmount,
        uint256 nativeTokenAmount
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        bytes memory payload = abi.encode(receiverAddress, btcTxnHash, lockedAmount, nativeTokenAmount);
        MessagingFee memory fee = _quote(chainEid, payload, MINT_OPTIONS, false);
        return (fee.nativeFee, fee.lzTokenFee);
    }

    function burnQuote(uint32 chainEid, address msgSender, bytes calldata rawTxn, uint256 unlockAmount)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        bytes memory payload = abi.encode(unlockAmount, msgSender, rawTxn);
        MessagingFee memory fee = _quote(chainEid, payload, BURN_OPTIONS, false);
        return (fee.nativeFee, fee.lzTokenFee);
    }
}

contract GasEstimatorScript is Script {
    // Amoy = 40267, Core = 40153, BSC = 40102, Sepolia = 40161 (for Testnets)
    // Polygon = 30109, Core = 30153, BSC = 30102, Ethereum = 30101 (for Mainnets)
    uint32 constant DST_CHAIN_EID = 40161; // Replace with actual destination chain EID
    uint32 constant SRC_CHAIN_EID = 40267; // Replace with actual source chain EID
    address constant USER_ADDRESS = 0xEE35AB43127933562c65A7942cbf1ccAac4BE86F; // Replace with actual receiver address
    bytes constant BURN_RAW_HEX =
        hex"63484E6964503842414A41434141414141554949754D4E6E625332446559336E4B6677793838454D3577516F7A4B762F2F38664C7745724F38413742414141414141442F2F2F2F2F417A516841414141414141414667415574364970734D48424443464E47786E524A6A746E6C39726A3658685341774141414141414142594146484851524B3633394249467165384F505868656654696E64732B68747745414141414141414157414254566F43693249525154616D50727A367A355468685461354368495141414141414141514572454363414141414141414169555343796B6C5A6C3952476B3742554832584547414C346E393548344154454854473761567A6B464E78547A4F304555616B4E594D684C56536C6C33387337305631494D55677135763549706D7931304152374E515176624A5161436673784D6253704653556D6A36537238716A6372612F75514C6368495037454F7034797A686872696B454138414170586666685A44464C5A306C493842377245526B6A6E55533365676F686B5966654D7558494C3264364A7136754C445A522F685A4D3832582F517274587A563349655667676C6D6C394B456B7570426A337A51685842616B4E594D684C56536C6C33387337305631494D55677135763549706D7931304152374E515176624A5159634F424B4D7A3559414C443963344F4F35314E57487033524C70523549464D4B795670754A7A776C6B42305567616B4E594D684C56536C6C33387337305631494D55677135763549706D7931304152374E515176624A5161744942704C6779647557303363382F66314A68577A58446D7745386C50574C6C42415A33664B2B653145566150724D414141414141";

    bytes32 ADDRESS_IN_BYTES32 = bytes32(uint256(uint160(USER_ADDRESS)));

    function run() external {
        _runMint();
        _runBurn();
    }

    function _runMint() internal {
        string memory srcRpcUrl = vm.envString("BASE_SEPOLIA_RPC_URL");
        vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory srcNetworkConfig = srcConfig.getConfig();

        vm.startBroadcast();
        GasEstimator gasEstimator = new GasEstimator(srcNetworkConfig.endpoint);
        console.log("Gas Estimator deployed to:", address(gasEstimator));
        gasEstimator.setPeer(DST_CHAIN_EID, ADDRESS_IN_BYTES32);
        (uint256 nativeGasRequired,) =
            gasEstimator.mintQuote(DST_CHAIN_EID, USER_ADDRESS, ADDRESS_IN_BYTES32, 100000000, 100000001);
        console.log("Native gas required for the mint txn:", nativeGasRequired);
        vm.stopBroadcast();
    }

    function _runBurn() internal {
        string memory destRpcUrl = vm.envString("BSC_TESTNET_RPC_URL");
        vm.createSelectFork(destRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory destNetworkConfig = destConfig.getConfig();

        vm.startBroadcast();
        GasEstimator gasEstimator = new GasEstimator(destNetworkConfig.endpoint);
        console.log("Gas Estimator deployed to:", address(gasEstimator));
        gasEstimator.setPeer(SRC_CHAIN_EID, ADDRESS_IN_BYTES32);
        (uint256 nativeGasRequired,) = gasEstimator.burnQuote(SRC_CHAIN_EID, USER_ADDRESS, BURN_RAW_HEX, 100000000);
        console.log("Native gas required for the burn txn:", nativeGasRequired);
        vm.stopBroadcast();
    }
}
