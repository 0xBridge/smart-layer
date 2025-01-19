// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {
    MessagingParams,
    ILayerZeroEndpointV2,
    MessagingFee
} from "lib/layerzero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MessageSender
 * @dev Contract for sending cross-chain messages using LayerZero V2
 */
contract MessageSender is Ownable {
    ILayerZeroEndpointV2 public immutable endpoint;

    // Mapping to store corresponding receiver addresses on different chains
    mapping(uint32 => bytes32) public receivers;

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);
    event ReceiverSet(uint32 dstEid, bytes32 receiver);

    constructor(address _endpoint) {
        transferOwnership(msg.sender);
        endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    /**
     * @dev Sets the receiver address for a specific chain
     * @param _dstEid The endpoint ID of the destination chain
     * @param _receiver The receiver address on the destination chain
     */
    function setReceiver(uint32 _dstEid, bytes32 _receiver) external onlyOwner {
        receivers[_dstEid] = _receiver;
        emit ReceiverSet(_dstEid, _receiver);
    }

    /**
     * @dev Sends a message to the specified chain
     * @param _dstEid The endpoint ID of the destination chain
     * @param _message The message to be sent
     */
    function sendMessage(uint32 _dstEid, string calldata _message) external payable {
        require(receivers[_dstEid] != bytes32(0), "Receiver not set"); // only set/whitelisted receivers can receive messages

        // Prepare send parameters
        bytes memory message = abi.encode(_message);

        MessagingParams memory sendParam = MessagingParams(_dstEid, receivers[_dstEid], message, "", false);

        // Calculate fees
        uint256 nativeFee = getNativeFeeToSendMessage(_dstEid, _message);
        require(msg.value >= nativeFee, "Insufficient native tokens");

        // Send the message
        endpoint.send{value: nativeFee}(sendParam, msg.sender);

        // Refund excess payment
        if (msg.value > nativeFee) {
            (bool success,) = msg.sender.call{value: msg.value - nativeFee}("");
            require(success, "Refund failed");
        }

        emit MessageSent(_dstEid, _message, receivers[_dstEid], nativeFee);
    }

    /**
     * @dev Allows the owner to withdraw any stuck tokens
     */
    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    function getNativeFeeToSendMessage(uint32 _dstEid, string calldata _message) public view returns (uint256) {
        require(receivers[_dstEid] != bytes32(0), "Receiver not set");

        // Prepare send message
        bytes memory message = abi.encode(_message);

        // Prepare send parameters
        MessagingParams memory sendParam = MessagingParams(_dstEid, receivers[_dstEid], message, "", false);

        // Calculate fees
        MessagingFee memory messagingFee = endpoint.quote(sendParam, address(this));
        return messagingFee.nativeFee;
    }
}
