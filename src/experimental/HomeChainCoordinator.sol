// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {BitcoinTxnParser} from "../libraries/BitcoinTxnParser.sol";

/**
 * @title HomeChainCoordinator
 * @dev Contract for coordinating cross-chain messages on the home chain
 */
contract HomeChainCoordinator is OApp, ReentrancyGuard, Pausable {
    // Mapping to store corresponding receiver addresses on different chains
    mapping(uint32 => bytes32) public receivers;
    mapping(address => bytes) public user_mintData; // TODO: Would require to store user address, AVS address, eBTC amount, chainID (to mint), psbt data (Also, timestamp?)

    // Events
    event MessageSent(uint32 dstEid, bytes message, bytes32 receiver, uint256 nativeFee);
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
    function sendMessage(uint32 _dstEid, bytes memory _message, bytes calldata _options) external payable {
        require(_message.length > 0, "Empty message");
        // TODO: Setup a trusted destination chain coordinator mapping to which the message can be sent (require here for the same)
        require(receivers[_dstEid] != bytes32(0), "Receiver not set");

        // TODO: Decode message and validate if the message is valid and came from the right source
        BitcoinTxnParser.TransactionMetadata memory metadata = decodeTransactionMetadata(_message);

        console2.logAddress(metadata.receiverAddress);
        console2.log("Locked amount: ", metadata.lockedAmount);
        console2.log("Chain ID: ", metadata.chainId);
        console2.log("Base token amount: ", metadata.baseTokenAmount);

        // TODO: Create a function to get the correct MessageFee for the user
        _lzSend(
            _dstEid,
            _message,
            _options,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender) // TODO: Check when does the refund happen and how much is refunded | How to know this value in advance?
        );

        console2.log("Emit event message sent");
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
        console2.log("Received message on home chain");
        console2.logBytes32(_guid);
        console2.logAddress(_executor);
        console2.logBytes(_message);
        console2.logBytes(_extraData);
    }

    function decodeTransactionMetadata(bytes memory rawTxnHex)
        public
        pure
        returns (BitcoinTxnParser.TransactionMetadata memory metadata)
    {
        // Parse transaction outputs
        bytes memory opReturnData = BitcoinTxnParser.decodeBitcoinTxn(rawTxnHex);
        // Decode metadata from OP_RETURN data
        return BitcoinTxnParser.decodeMetadata(opReturnData);
    }

    fallback() external payable {
        // Fallback function to receive native tokens
    }

    receive() external payable {
        // Receive native tokens
    }
}
