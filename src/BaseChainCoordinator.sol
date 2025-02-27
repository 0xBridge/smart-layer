// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OApp, Origin, MessagingFee, OAppReceiver} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {MintData, IBaseChainCoordinator, ILayerZeroReceiver} from "./interfaces/IBaseChainCoordinator.sol";
import {eBTCManager} from "./eBTCManager.sol";

/**
 * @title BaseChainCoordinator
 * @notice Contract for coordinating cross-chain messages on the base chain
 * @dev Handles receiving and processing cross-chain messages for the eBTC system
 */
contract BaseChainCoordinator is OApp, ReentrancyGuard, Pausable, IBaseChainCoordinator {
    // Errors
    error MessageAlreadyProcessed(bytes32 btcTxnHash);
    error InvalidMessageSender();
    error InvalidPeer();
    error ReceiverNotSet();
    error WithdrawalFailed();

    // State variables
    mapping(bytes32 => MintData) internal _btcTxnHash_mintData;
    eBTCManager internal _eBTCManagerInstance;
    uint32 internal immutable _chainEid;

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);
    event MessageProcessed(
        bytes32 guid, uint32 srcEid, bytes32 sender, address user, bytes32 btcTxnHash, uint256 lockedAmount
    );

    /**
     * @notice Initializes the BaseChainCoordinator contract
     * @param endpoint_ Address of the LayerZero endpoint
     * @param owner_ Address of the contract owner
     * @param eBTCManager_ Address of the eBTC manager contract
     * @param chainEid_ The endpoint ID of the current chain
     */
    constructor(address endpoint_, address owner_, address eBTCManager_, uint32 chainEid_) OApp(endpoint_, owner_) {
        _transferOwnership(owner_);
        _eBTCManagerInstance = eBTCManager(eBTCManager_);
        _chainEid = chainEid_;
    }

    /**
     * @notice Sets the peer address for a specific chain
     * @param _dstEid The endpoint ID of the destination chain
     * @param _peer The receiver address on the destination chain
     * @dev Only callable by the contract owner
     */
    function setPeer(uint32 _dstEid, bytes32 _peer) public override onlyOwner {
        if (_peer == bytes32(0)) revert InvalidPeer();
        super.setPeer(_dstEid, _peer);
    }

    /**
     * @notice Sends a message to the specified chain
     * @param _dstEid The endpoint ID of the destination chain
     * @param _message The message to send
     * @param _options Message execution options (e.g., for sending gas to destination)
     * @dev Payable function that accepts native gas for message fee
     */
    function sendMessage(uint32 _dstEid, string memory _message, bytes calldata _options) external payable {
        if (peers[_dstEid] == bytes32(0)) revert ReceiverNotSet();

        // Prepare send payload
        bytes memory _payload = abi.encode(_message);
        _lzSend(
            _dstEid,
            _payload,
            _options,
            MessagingFee(msg.value, 0), // Fee in native gas and ZRO token.
            payable(msg.sender) // Refund address in case of failed source message.
        );

        emit MessageSent(_dstEid, _message, peers[_dstEid], msg.value);
    }

    /**
     * @notice Sets the eBTC manager contract
     * @param _eBTCManager Address of the new eBTC manager
     * @dev Only callable by the contract owner
     */
    function setEBTCManager(address _eBTCManager) external onlyOwner {
        _eBTCManagerInstance = eBTCManager(payable(_eBTCManager));
    }

    /**
     * @notice Receives messages from LayerZero
     * @param _origin The origin information of the message
     * @param _guid The unique identifier for the message
     * @param _message The message payload
     * @param _executor The address executing the message
     * @param _extraData Additional data for message processing
     * @dev Only processes messages when contract is not paused
     */
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) public payable virtual override(OAppReceiver, ILayerZeroReceiver) whenNotPaused {
        _lzReceive(_origin, _guid, _message, _executor, _extraData);
    }

    /**
     * @notice Internal function to process received messages from LayerZero
     * @param _origin The origin information of the message
     * @param _guid The unique identifier for the message
     * @param _message The message payload
     * @dev The executor address (unused but kept for interface compatibility)
     * @dev The extra data (unused but kept for interface compatibility)
     * @dev Validates sender and processes the message
     */
    function _lzReceive(Origin calldata _origin, bytes32 _guid, bytes calldata _message, address, bytes calldata)
        internal
        virtual
        override
        whenNotPaused
    {
        if (!(msg.sender == address(endpoint) || msg.sender == address(uint160(uint256(peers[_chainEid]))))) {
            revert InvalidMessageSender();
        }

        (address user, bytes32 btcTxnHash, uint256 lockedAmount, uint256 nativeTokenAmount) =
            abi.decode(_message, (address, bytes32, uint256, uint256));

        // 1. Check for replay attacks
        _validateMessageUniqueness(btcTxnHash);

        // 2. Process the message
        _processMessage(btcTxnHash, user, lockedAmount);

        emit MessageProcessed(_guid, _origin.srcEid, _origin.sender, user, btcTxnHash, lockedAmount);
    }

    /**
     * @notice Validates that a message hasn't been processed before
     * @param _btcTxnHash The Bitcoin transaction hash
     * @dev Reverts if message has already been processed (commented out for testing)
     */
    function _validateMessageUniqueness(bytes32 _btcTxnHash) internal view {
        // Check if this message has already been processed
        if (isMessageProcessed(_btcTxnHash)) {
            revert MessageAlreadyProcessed(_btcTxnHash);
        }
    }

    /**
     * @notice Processes a received message
     * @param _btcTxnHash The Bitcoin transaction hash
     * @param _user The recipient user address
     * @param _lockedAmount The amount of BTC locked
     * @dev Updates storage and handles minting
     */
    function _processMessage(bytes32 _btcTxnHash, address _user, uint256 _lockedAmount) internal {
        // Decode the message and process it
        MintData memory mintData = _btcTxnHash_mintData[_btcTxnHash];
        mintData.isMinted = true;
        mintData.user = _user;
        mintData.lockedAmount = _lockedAmount;
        _btcTxnHash_mintData[_btcTxnHash] = mintData;
        // Additional processing based on message content
        _handleMinting(_user, _lockedAmount);
    }

    /**
     * @notice Handles the minting of eBTC tokens
     * @param _user The recipient user address
     * @param _lockedAmount The amount to mint
     * @dev Calls the eBTC manager to mint tokens
     */
    function _handleMinting(address _user, uint256 _lockedAmount) internal {
        _eBTCManagerInstance.mint(_user, _lockedAmount);
    }

    /**
     * @notice Retrieves transaction data for a specific Bitcoin transaction
     * @param _btcTxnHash The Bitcoin transaction hash
     * @return The mint data associated with the transaction
     */
    function getTxnData(bytes32 _btcTxnHash) external view returns (MintData memory) {
        return _btcTxnHash_mintData[_btcTxnHash];
    }

    /**
     * @notice Checks if a message has been processed
     * @param _btcTxnHash The unique identifier of the message
     * @return True if message has been processed
     */
    function isMessageProcessed(bytes32 _btcTxnHash) public view returns (bool) {
        return _btcTxnHash_mintData[_btcTxnHash].isMinted;
    }

    /**
     * @notice Checks if a chain and sender combination is trusted
     * @param _srcEid The source chain endpoint ID
     * @param _sender The sender address in bytes32 format
     * @return True if the combination is trusted
     */
    function isTrustedSender(uint32 _srcEid, bytes32 _sender) external view returns (bool) {
        return peers[_srcEid] == _sender;
    }

    /**
     * @notice Pauses the contract
     * @dev Only callable by the contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by the contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Withdraws stuck funds from the contract
     * @dev Only callable by the contract owner, for emergency use only
     */
    function withdraw() external onlyOwner nonReentrant {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert WithdrawalFailed();
    }
}
