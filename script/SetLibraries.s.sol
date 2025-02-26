// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Forge imports
import {Script, console} from "forge-std/Script.sol";
// LayerZero imports
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract SetLibraries is Script {
    // HomeChainCoordinator (Holesky)
    address _endpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address _oapp = 0x3505bb3aC00E33c1463689F1987ADce0466215D3;
    address _sendLib = 0x21F33EcF7F65D61f77e554B4B4380829908cD076;
    address _receiveLib = 0xbAe52D605770aD2f0D17533ce56D146c7C964A0d;

    // BaseChainCoordinator (Core)
    // address _endpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    // address _oapp = 0x40797ded5773bd5f981ce4ECdc7c7BC9FC65b854;
    // address _sendLib = 0xc8361Fac616435eB86B9F6e2faaff38F38B0d68C;
    // address _receiveLib = 0xD1bbdB62826eDdE4934Ff3A4920eB053ac9D5569;

    // From where is the request coming from
    uint32 _eid = 40153; // 40153 for Core, 40217 for Holesky, 40102 for BSC Testnet

    function run() external {
        uint256 aggregatorPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        string memory rpcUrl = vm.envString("HOLESKY_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Initialize the endpoint contract
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(_endpoint);

        // Start broadcasting transactions
        vm.startBroadcast(aggregatorPrivateKey);

        // Set the send library
        endpoint.setSendLibrary(_oapp, _eid, _sendLib);
        console.log("Send library set successfully.");

        // Set the receive library
        uint256 _gracePeriod = 0;
        endpoint.setReceiveLibrary(_oapp, _eid, _receiveLib, _gracePeriod);
        console.log("Receive library set successfully.");

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
