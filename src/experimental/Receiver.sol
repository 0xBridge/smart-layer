// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {
    MessagingParams,
    ILayerZeroEndpointV2,
    MessagingFee
} from "lib/layerzero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MessageReceiver
 * @dev Contract for receiving cross-chain messages using LayerZero V2
 */
contract MessageReceiver is Ownable {
    ILayerZeroEndpointV2 public immutable endpoint;

    // Events
    event MessageReceived(uint32 srcEid, bytes32 sender, string message);

    constructor(address _endpoint) Ownable(msg.sender) {
        endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    /**
     * @dev Handles incoming messages from LayerZero
     * @param _origin The origin information of the message
     * @param _sender The sender of the message
     * @param _payload The message payload
     */
    function lzReceive(Origin calldata _origin, bytes32 _sender, bytes calldata _payload) external {
        require(msg.sender == address(endpoint), "Invalid endpoint");

        // Decode the message
        string memory message = abi.decode(_payload, (string));

        emit MessageReceived(_origin.srcEid, _sender, message);
    }
}
