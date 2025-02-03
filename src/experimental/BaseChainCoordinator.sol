// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {MintData, IBaseChainCoordinator} from "./interfaces/IBaseChainCoordinator.sol";
import {IERC20} from "lib/eigenlayer-middleware/lib/forge-std/src/interfaces/IERC20.sol";

/**
 * @title BaseChainCoordinator
 * @dev Contract for coordinating cross-chain messages on the base chain
 */
contract BaseChainCoordinator is OApp, ReentrancyGuard, Pausable, IBaseChainCoordinator {
    // Errors
    error InvalidSource(uint32 srcEid, bytes32 sender);
    error InvalidMessageFormat();
    error MessageAlreadyProcessed(bytes32 messageHash);
    error InvalidSignature();

    // Mapping to store corresponding receiver addresses on different chains
    // TODO: Check if isGuidProcessed mapping is required
    mapping(bytes32 => MintData) public messageHash_mintData;
    IERC20 private eBTC;

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);
    event MessageValidated(bytes32 guid, uint32 srcEid, bytes32 sender);

    constructor(address _endpoint, address _eBTC, address _owner) OApp(_endpoint, _owner) {
        _transferOwnership(_owner);
        eBTC = IERC20(_eBTC);
        // endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    /**
     * @dev Sets the peer address for a specific chain _dstEid
     * @param _dstEid The endpoint ID of the destination chain
     * @param _peer The receiver address on the destination chain
     */
    function setPeer(uint32 _dstEid, bytes32 _peer) public override onlyOwner {
        require(_peer != bytes32(0), "Invalid receiver");
        super.setPeer(_dstEid, _peer);
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
        require(peers[_dstEid] != bytes32(0), "Receiver not set");

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

        emit MessageSent(_dstEid, _message, peers[_dstEid], msg.value);
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid, // TODO: Check if this is already checked at the endpoint level if is processed
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal virtual override {
        // TODO: Verify contract signature here and set a secondary state variable to mint the eBTC
        console.log("Received message on home chain");
        console.logBytes32(_guid);
        console.logAddress(_executor);
        console.logBytes(_message);
        console.logBytes(_extraData);

        (uint32 chainId, address user, uint256 eBTCAmount) = abi.decode(_message, (uint32, address, uint256));

        // 0. Create keccak256 hash of the message
        bytes32 messageHash = keccak256(_message);

        // 1. Validate source chain and sender
        _validateSourceAndSender(_origin, chainId);

        // 2. Check for replay attacks
        _validateMessageUniqueness(messageHash);

        // 3. Validate message format
        // _validateMessageFormat(_message);

        // 4. Check the message has not been processed

        // 4. Process the message
        _processMessage(messageHash, chainId, user, eBTCAmount);

        emit MessageValidated(_guid, _origin.srcEid, _origin.sender);
    }

    function _validateSourceAndSender(Origin calldata _origin, uint32 chainId) internal view {
        // Verify the sender matches our stored peer for this chain
        if (_origin.sender != peers[_origin.srcEid] || chainId != block.chainid) {
            revert InvalidSource(_origin.srcEid, _origin.sender);
        }
    }

    function _validateMessageUniqueness(bytes32 _messageHash) internal view {
        // Check if this message has already been processed
        if (isMessageProcessed(_messageHash)) {
            revert MessageAlreadyProcessed(_messageHash);
        }
    }

    // function _validateMessageFormat(bytes calldata _message) internal pure {
    //     // Validate message format based on your specific requirements
    //     // For example, if expecting an abi.encoded struct:
    //     if (_message.length < 32) {
    //         revert InvalidMessageFormat();
    //     }

    //     // Add any specific message format validation
    //     try this.decodeMessage(_message) returns (bool) {
    //         // Message decoded successfully
    //     } catch {
    //         revert InvalidMessageFormat();
    //     }
    // }

    function _processMessage(bytes32 _messageHash, uint32 _chainId, address _user, uint256 _eBTCAmount) internal {
        // Decode the message and process it

        // Your existing message processing logic
        MintData memory mintData = messageHash_mintData[_messageHash];
        mintData.isMinted = true;
        mintData.chainId = _chainId;
        mintData.user = _user;
        mintData.eBTCAmount = _eBTCAmount;
        // Additional processing based on message content
        _handleMinting(_user, _eBTCAmount);
        messageHash_mintData[_messageHash] = mintData;
    }

    function _handleMinting(address _user, uint256 _eBTCAmount) internal {
        // Your minting logic here
        // eBTC.mint(_user, _eBTCAmount);
    }

    function decodeMessage(bytes calldata _message) external pure returns (bool) {
        // Example decoding - adjust based on your message format
        (bytes memory actualMessage) = abi.decode(_message, (bytes));
        require(actualMessage.length > 0, "Empty message content");
        return true;
    }

    /**
     * @dev Get the status of a message processing
     * @param _messageHash The unique identifier of the message
     * @return bool True if message has been processed
     */
    function isMessageProcessed(bytes32 _messageHash) public view returns (bool) {
        return messageHash_mintData[_messageHash].isMinted;
    }

    /**
     * @dev Check if a chain and sender combination is trusted
     * @param _srcEid The source chain endpoint ID
     * @param _sender The sender address in bytes32 format
     * @return bool True if the combination is trusted
     */
    function isTrustedSender(uint32 _srcEid, bytes32 _sender) external view returns (bool) {
        return peers[_srcEid] == _sender;
    }

    /**
     * @dev Allows the owner to withdraw any stuck tokens
     */
    function withdraw() external onlyOwner nonReentrant {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    receive() external payable {}
}
