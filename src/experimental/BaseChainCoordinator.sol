// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title BaseChainCoordinator
 * @dev Contract for coordinating cross-chain messages on the base chain
 */
contract BaseChainCoordinator is OApp, ReentrancyGuard, Pausable {
    // Mapping to store corresponding receiver addresses on different chains
    mapping(uint32 => bytes32) public receivers;
    mapping(address => bytes) public user_mintData; // TODO: Would require to store user address, AVS address, eBTC amount, chainID (to mint), psbt data (Also, timestamp?)
    bytes public temp_message;

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);
    event ReceiverSet(uint32 dstEid, bytes32 receiver);

    constructor(address _endpoint, address _owner) OApp(_endpoint, _owner) {
        _transferOwnership(_owner);
        // endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    /**
     * @dev Sets the receiver address for a specific chain
     * @param _dstEid The endpoint ID of the destination chain
     * @param _receiver The receiver address on the destination chain
     */
    function setReceiver(uint32 _dstEid, bytes32 _receiver) external onlyOwner {
        require(_receiver != bytes32(0), "Invalid receiver");
        receivers[_dstEid] = _receiver;
        setPeer(_dstEid, _receiver);
        emit ReceiverSet(_dstEid, _receiver);
    }

    /**
     * @dev Sends a message to the specified chain
     * @param _dstEid The endpoint ID of the destination chain
     * @param _message The message to send
     * @param _options Message execution options (e.g., for sending gas to destination)
     */
    function sendMessage(uint32 _dstEid, string memory _message, bytes calldata _options) external payable {
        // require(_message.length > 0, "Empty payload");

        // TODO: Setup a trusted destination chain coordinator mapping to which the message can be sent (require here for the same)
        require(receivers[_dstEid] != bytes32(0), "Receiver not set");

        // Prepare send payload
        bytes memory _payload = abi.encode(_message);
        _lzSend(
            _dstEid,
            _payload,
            _options,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender)
        );

        emit MessageSent(_dstEid, _message, receivers[_dstEid], msg.value);
    }

    /**
     * @dev Allows the owner to withdraw any stuck tokens
     */
    function withdraw() external onlyOwner nonReentrant {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal virtual override {
        // Implement the receive logic here
        console.log("Received message on home chain");
        console.logBytes32(_guid);
        console.logAddress(_executor);
        console.logBytes(_message);
        console.logBytes(_extraData);
        temp_message = _message;
    }

    // function getNativeFeeToSendMessage(uint32 _dstEid, string calldata _message) public view returns (uint256) {
    //     require(receivers[_dstEid] != bytes32(0), "Receiver not set");

    //     // Prepare send payload
    //     bytes memory payload = abi.encode(_message);

    //     // Prepare send parameters
    //     MessagingParams memory sendParam = MessagingParams(_dstEid, receivers[_dstEid], payload, "", false);

    //     // Calculate fees
    //     MessagingFee memory messagingFee = endpoint.quote(sendParam, address(this));
    //     return messagingFee.nativeFee;
    // }
}
