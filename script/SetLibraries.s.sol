// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Forge imports
import {Script, console} from "forge-std/Script.sol";
// LayerZero imports
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/**
 * @title SetLibraries
 * @notice Script to set LayerZero libraries for cross-chain messaging
 * @dev Configures send and receive libraries for a LayerZero OApp
 */
contract SetLibraries is Script {
    // Constants
    // HomeChainCoordinator (Holesky)
    address internal constant ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address internal constant OAPP = 0x3505bb3aC00E33c1463689F1987ADce0466215D3;
    address internal constant SEND_LIB = 0x21F33EcF7F65D61f77e554B4B4380829908cD076;
    address internal constant RECEIVE_LIB = 0xbAe52D605770aD2f0D17533ce56D146c7C964A0d;

    // From where is the request coming from
    uint32 internal constant EID = 40153; // 40153 for Core, 40217 for Holesky, 40102 for BSC Testnet

    /**
     * @notice Main execution function
     * @dev Sets send and receive libraries for the specified OApp
     */
    function run() external {
        uint256 aggregatorPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        string memory rpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Initialize the endpoint contract
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(ENDPOINT);

        // Start broadcasting transactions
        vm.startBroadcast(aggregatorPrivateKey);

        // Set the send library
        endpoint.setSendLibrary(OAPP, EID, SEND_LIB);
        console.log("Send library set successfully.");

        // Set the receive library
        uint256 gracePeriod = 0;
        endpoint.setReceiveLibrary(OAPP, EID, RECEIVE_LIB, gracePeriod);
        console.log("Receive library set successfully.");

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
