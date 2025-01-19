// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {
    Origin,
    MessagingParams,
    ILayerZeroEndpointV2,
    MessagingFee,
    MessagingReceipt
} from "lib/layerzero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MessageReceiver
 * @dev Contract for receiving cross-chain messages using LayerZero V2
 */
contract MessageReceiver {
    address public immutable endpoint;
    address public immutable owner;

    // Map of trusted source addresses on different chains
    mapping(uint32 => bytes32) public trustedRemotes;

    event MessageReceived(uint32 indexed srcEid, bytes32 sender, bytes payload);
    event TempEvent(address executor, bytes extraData);

    error UntrustedSource();
    error UnauthorizedEndpoint();
    error InvalidSender();

    constructor(address _endpoint) {
        endpoint = _endpoint;
        owner = msg.sender;
    }

    /**
     * @dev Receives messages from LayerZero
     * @param _origin The origin information of the message
     * @param _guid The unique identifier of the message
     * @param _message The message payload
     * @param _executor Address of the executor (unused in this example)
     * @param _extraData Additional data (unused in this example)
     */
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external returns (MessagingReceipt memory receipt) {
        // Verify the caller is the LayerZero endpoint
        if (msg.sender != endpoint) revert UnauthorizedEndpoint();

        // Verify the message is from a trusted source
        if (trustedRemotes[_origin.srcEid] == bytes32(0)) revert UntrustedSource();

        // Verify the sender matches our trusted remote
        if (_origin.sender != trustedRemotes[_origin.srcEid]) revert InvalidSender(); // TODO: Add contract signature verification here

        // Decode the message
        // In this example, assuming a simple string message
        (string memory receivedMessage) = abi.decode(_message, (string));

        // Emit event for tracking
        emit MessageReceived(_origin.srcEid, _origin.sender, _message);
        emit TempEvent(_executor, _extraData);

        // Process the message
        _processMessage(receivedMessage);

        // Return receipt (optional, can be empty)
        MessagingFee memory fee = MessagingFee(0, 0);
        return MessagingReceipt(_guid, uint64(0), fee);
    }

    /**
     * @dev Sets trusted remote addresses for each chain
     * @param _srcEid The source endpoint ID
     * @param _srcAddress The trusted source address on that chain
     */
    function setTrustedRemote(uint32 _srcEid, bytes32 _srcAddress) external {
        require(msg.sender == owner, "Only owner");
        trustedRemotes[_srcEid] = _srcAddress;
    }

    /**
     * @dev Internal function to process the received message
     * @param _message The decoded message
     */
    function _processMessage(string memory _message) internal {
        // Implement your message processing logic here
        // Make sure to handle any potential failures gracefully
        // decode the message and process it
    }
}
