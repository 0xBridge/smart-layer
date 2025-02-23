// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {MintData, IBaseChainCoordinator} from "./interfaces/IBaseChainCoordinator.sol";
import {eBTCManager} from "./eBTCManager.sol";

/**
 * @title BaseChainCoordinator
 * @dev Contract for coordinating cross-chain messages on the base chain
 */
contract BaseChainCoordinator is OApp, ReentrancyGuard, Pausable, IBaseChainCoordinator {
    // Errors
    error MessageAlreadyProcessed(bytes32 btcTxnHash);
    error InvalidMessageSender();
    error InvalidPeer();
    error ReceiverNotSet();
    error WithdrawalFailed();

    // Mapping to store corresponding receiver addresses on different chains
    mapping(bytes32 => MintData) private btcTxnHash_mintData;
    eBTCManager private eBTCManagerInstance;

    // Events
    event MessageSent(uint32 dstEid, string message, bytes32 receiver, uint256 nativeFee);
    event MessageProcessed(
        bytes32 guid, uint32 srcEid, bytes32 sender, address user, bytes32 btcTxnHash, uint256 lockedAmount
    );

    constructor(address _endpoint, address _owner, address _eBTCManager) OApp(_endpoint, _owner) {
        _transferOwnership(_owner);
        eBTCManagerInstance = eBTCManager(_eBTCManager);
    }

    /**
     * @dev Sets the peer address for a specific chain _dstEid
     * @param _dstEid The endpoint ID of the destination chain
     * @param _peer The receiver address on the destination chain
     */
    function setPeer(uint32 _dstEid, bytes32 _peer) public override onlyOwner {
        if (_peer == bytes32(0)) revert InvalidPeer();
        super.setPeer(_dstEid, _peer);
    }

    /**
     * @dev Sends a message to the specified chain
     * @param _dstEid The endpoint ID of the destination chain
     * @param _message The message to send
     * @param _options Message execution options (e.g., for sending gas to destination)
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

    function setEBTCManager(address _eBTCManager) external onlyOwner {
        eBTCManagerInstance = eBTCManager(payable(_eBTCManager));
    }

    function _lzReceive(Origin calldata _origin, bytes32 _guid, bytes calldata _message, address, bytes calldata)
        internal
        virtual
        override
        whenNotPaused
    {
        if (msg.sender != address(endpoint)) revert InvalidMessageSender();

        (address user, bytes32 btcTxnHash, uint256 lockedAmount, uint256 nativeTokenAmount) =
            abi.decode(_message, (address, bytes32, uint256, uint256));

        // 1. Check for replay attacks
        _validateMessageUniqueness(btcTxnHash);

        // 2. Process the message
        _processMessage(btcTxnHash, user, lockedAmount);

        emit MessageProcessed(_guid, _origin.srcEid, _origin.sender, user, btcTxnHash, lockedAmount);
    }

    function _validateMessageUniqueness(bytes32 _btcTxnHash) internal view {
        // Check if this message has already been processed
        // TODO: Removed for Amit and Rahul's testing | Please add this back
        // if (isMessageProcessed(_btcTxnHash)) {
        //     revert MessageAlreadyProcessed(_btcTxnHash);
        // }
    }

    function _processMessage(bytes32 _btcTxnHash, address _user, uint256 _lockedAmount) internal {
        // Decode the message and process it
        MintData memory mintData = btcTxnHash_mintData[_btcTxnHash];
        mintData.isMinted = true;
        mintData.user = _user;
        mintData.lockedAmount = _lockedAmount;
        btcTxnHash_mintData[_btcTxnHash] = mintData;
        // Additional processing based on message content
        _handleMinting(_user, _lockedAmount);
    }

    function _handleMinting(address _user, uint256 _lockedAmount) internal {
        eBTCManagerInstance.mint(_user, _lockedAmount);
    }

    function getTxnData(bytes32 _btcTxnHash) external view returns (MintData memory) {
        return btcTxnHash_mintData[_btcTxnHash];
    }

    /**
     * @dev Get the status of a message processing
     * @param _btcTxnHash The unique identifier of the message
     * @return bool True if message has been processed
     */
    function isMessageProcessed(bytes32 _btcTxnHash) public view returns (bool) {
        return btcTxnHash_mintData[_btcTxnHash].isMinted;
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
     * @dev Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Withdraw stuck funds (emergency only)
     */
    function withdraw() external onlyOwner nonReentrant {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert WithdrawalFailed();
    }
}
