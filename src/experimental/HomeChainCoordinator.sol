// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {BitcoinTxnParser} from "../libraries/BitcoinTxnParser.sol";
import {PSBTMetadata} from "./interfaces/IHomeChainCoordinator.sol";
import {TxidCalculator} from "../libraries/TxidCalculator.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {BitcoinLightClient} from "../BitcoinLightClient.sol";
import {BitcoinUtils} from "../libraries/BitcoinUtils.sol";

/**
 * @title HomeChainCoordinator
 * @dev Contract for coordinating cross-chain messages on the home chain
 */
contract HomeChainCoordinator is OApp, ReentrancyGuard, Pausable {
    // Errors
    error TxnAlreadyProcessed(bytes32 btcTxnHash);
    error InvalidPSBTData();
    error InvalidAmount(uint256 amount);
    error InvalidDestination(address receiver);
    error InvalidReceiver();
    error BitcoinTxnNotFound();
    error BitcoinTxnAndPSBTMismatch();
    error InvalidPeer();
    error WithdrawalFailed();

    // State variables
    BitcoinLightClient private lightClient;

    address private taskManager;
    mapping(bytes32 => PSBTMetadata) private btcTxnHash_psbtMetadata;

    uint256 public maxGasTokenAmount = 1 ether; // Max amount that can be put as the native token amount
    uint256 public minBTCAmount = 1000; // Min BTC amount / satoshis that needs to be locked

    // Events
    event MessageSent(uint32 indexed dstEid, bytes32 indexed psbtHash, address indexed operator, uint256 timestamp);
    event OperatorStatusChanged(address indexed operator, bool status);

    constructor(address _lightClient, address _endpoint, address _owner) OApp(_endpoint, _owner) {
        _transferOwnership(_owner);
        lightClient = BitcoinLightClient(_lightClient);
    }

    /**
     * @dev Sets the maximum amount of gas tokens that can be used.
     * @param _maxGasTokenAmount The maximum gas token amount to set.
     */
    function setMaxGasTokenAmount(uint256 _maxGasTokenAmount) external onlyOwner {
        if (_maxGasTokenAmount == 0) revert InvalidAmount(_maxGasTokenAmount);
        maxGasTokenAmount = _maxGasTokenAmount;
    }

    /**
     * @dev Sets the minimum amount of BTC that needs to be locked.
     * @param _minBtcAmount The minimum BTC amount to set.
     */
    function setMinBtcAmount(uint256 _minBtcAmount) external onlyOwner {
        if (_minBtcAmount == 0) revert InvalidAmount(_minBtcAmount);
        minBTCAmount = _minBtcAmount;
    }

    /**
     * @dev Sets the peer address for a specific chain.
     * @param _dstEid The endpoint ID of the destination chain.
     * @param _peer The receiver address on the destination chain.
     */
    function setPeer(uint32 _dstEid, bytes32 _peer) public override onlyOwner {
        if (_peer == bytes32(0)) revert InvalidPeer();
        super.setPeer(_dstEid, _peer);
    }

    // TODO: The message will come from the endpoint but for now we're considering it to be the owner
    // TODO: Check if the message is coming from the task manager

    /**
     * @dev Submits a block and sends a message with PSBT data.
     * @param rawHeader The raw block header.
     * @param intermediateHeaders The intermediate headers for the block.
     * @param _btcTxnHash The BTC transaction hash.
     * @param _proof The proof for the transaction.
     * @param _index The index of the transaction in the block.
     * @param _psbtData The PSBT data to be processed.
     * @param _options LayerZero message options.
     * @param _refundAddress The address to refund in case of failure.
     */
    function submitBlockAndSendMessage(
        bytes calldata rawHeader,
        bytes[] calldata intermediateHeaders,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _psbtData,
        bytes calldata _options,
        address _refundAddress
    ) external payable whenNotPaused nonReentrant onlyOwner {
        // 0. Submit block header along with intermediate headers to light client
        bytes32 blockHash = lightClient.submitRawBlockHeader(rawHeader, intermediateHeaders);
        // 1. Get merkle root to validate txn
        bytes32 merkleRoot = lightClient.getMerkleRootForBlock(blockHash);
        // 2. Send message
        _sendMessage(merkleRoot, _btcTxnHash, _proof, _index, _psbtData, _options, _refundAddress);
    }

    /**
     * @dev Sends a cross-chain message with PSBT data.
     * @param _blockHash The block hash to validate the transaction.
     * @param _btcTxnHash The BTC transaction hash.
     * @param _proof The proof for the transaction.
     * @param _index The index of the transaction in the block.
     * @param _psbtData The PSBT data to be processed.
     * @param _options LayerZero message options.
     * @param _refundAddress The address to refund in case of failure.
     */
    function sendMessage(
        bytes32 _blockHash,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _psbtData,
        bytes calldata _options,
        address _refundAddress
    ) external payable whenNotPaused nonReentrant onlyOwner {
        bytes32 merkleRoot = lightClient.getMerkleRootForBlock(_blockHash);
        _sendMessage(merkleRoot, _btcTxnHash, _proof, _index, _psbtData, _options, _refundAddress);
    }

    /**
     * @dev Internal function to send a cross-chain message with PSBT data.
     * @param _merkleRoot The merkle root for the block.
     * @param _btcTxnHash The BTC transaction hash.
     * @param _proof The proof for the transaction.
     * @param _index The index of the transaction in the block.
     * @param _psbtData The PSBT data to be processed.
     * @param _options LayerZero message options.
     * @param _refundAddress The address to refund in case of failure.
     */
    function _sendMessage(
        bytes32 _merkleRoot,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _psbtData,
        bytes calldata _options,
        address _refundAddress
    ) internal {
        // 0. btcTxnHash generated from the psbt data being shared should be the same as the one passed
        bytes32 txid = TxidCalculator.calculateTxid(_psbtData);
        if (txid != _btcTxnHash) {
            revert BitcoinTxnAndPSBTMismatch();
        }

        // 1. Parse and validate PSBT data
        BitcoinTxnParser.TransactionMetadata memory metadata = _validatePSBTData(_psbtData);

        // 2. TODO: Get _dstEid for a specific metadata.chainId from LayerZero contract
        uint32 _dstEid = metadata.chainId == 8453 ? 30184 : metadata.chainId;

        // 3. Check if the message already exists or is processed
        if (btcTxnHash_psbtMetadata[_btcTxnHash].isMinted) {
            revert TxnAlreadyProcessed(_btcTxnHash);
        }

        // 4. Validate receiver is set for destination chain
        if (peers[_dstEid] == bytes32(0)) {
            revert InvalidReceiver();
        }

        // 5. Validate txn with SPV data
        if (!BitcoinUtils.verifyTxInclusion(_btcTxnHash, _merkleRoot, _proof, _index)) revert BitcoinTxnNotFound();

        // TODO: This needs to come from the metadata itself as this will keep on changing
        bytes32 networkPublicKey;
        // 6. Store PSBT metadata
        PSBTMetadata memory psbtMetaData = PSBTMetadata({
            isMinted: true,
            chainId: metadata.chainId,
            user: metadata.receiverAddress,
            lockedAmount: metadata.lockedAmount,
            nativeTokenAmount: metadata.nativeTokenAmount,
            networkPublicKey: networkPublicKey,
            psbtData: _psbtData
        });
        btcTxnHash_psbtMetadata[_btcTxnHash] = psbtMetaData;

        // 7. Send message through LayerZerobytes memory payload
        bytes memory payload = abi.encode(
            metadata.chainId, metadata.receiverAddress, _btcTxnHash, metadata.lockedAmount, metadata.nativeTokenAmount
        );

        // TODO: Create a function to get the correct MessageFee for the user
        _lzSend(
            _dstEid,
            payload,
            _options,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            _refundAddress
        );

        emit MessageSent(_dstEid, _btcTxnHash, msg.sender, block.timestamp);
    }

    /**
     * @dev Validates PSBT data and extracts metadata.
     * @param _psbtData The PSBT data to validate.
     * @return metadata The extracted transaction metadata.
     */
    function _validatePSBTData(bytes calldata _psbtData)
        internal
        view
        returns (BitcoinTxnParser.TransactionMetadata memory)
    {
        if (_psbtData.length == 0) {
            revert InvalidPSBTData();
        }

        // Parse transaction outputs and metadata
        bytes memory opReturnData = BitcoinTxnParser.decodeBitcoinTxn(_psbtData);
        BitcoinTxnParser.TransactionMetadata memory metadata = BitcoinTxnParser.decodeMetadata(opReturnData);

        // Validate amounts
        if (metadata.nativeTokenAmount > maxGasTokenAmount) {
            revert InvalidAmount(metadata.nativeTokenAmount);
        }
        if (metadata.lockedAmount < minBTCAmount) {
            revert InvalidAmount(metadata.lockedAmount);
        }

        // Validate receiver address
        if (metadata.receiverAddress == address(0)) {
            revert InvalidDestination(metadata.receiverAddress);
        }

        return metadata;
    }

    /**
     * @dev Sends a message for a specific receiver with the given BTC transaction hash.
     * @param _receiver The address of the receiver.
     * @param _btcTxnHash The BTC transaction hash.
     * @param _options LayerZero message options.
     * @param _refundAddress The address to refund in case of failure.
     */
    function sendMessageFor(address _receiver, bytes32 _btcTxnHash, bytes calldata _options, address _refundAddress)
        external
        payable
    {
        if (btcTxnHash_psbtMetadata[_btcTxnHash].user != _receiver) {
            revert InvalidReceiver(); // This also ensures that the txn is already present
        }

        // 1. Parse and get metadata from psbtMetaData
        PSBTMetadata memory metadata = btcTxnHash_psbtMetadata[_btcTxnHash];

        // 2. TODO: Get _dstEid for a specific metadata.chainId from LayerZero contract
        uint32 _dstEid = metadata.chainId == 8453 ? 30184 : metadata.chainId;

        // 3. Validate receiver is set for destination chain
        if (peers[_dstEid] == bytes32(0)) {
            revert InvalidReceiver();
        }

        // 4. Check if all the fields needed to be sent in the payload are present in the metadata (should never enter revert ideally)
        if (metadata.chainId == 0 || metadata.user == address(0) || metadata.lockedAmount == 0) {
            revert InvalidPSBTData();
        }

        // 5. Send message through LayerZerobytes memory payload =
        bytes memory payload =
            abi.encode(metadata.chainId, metadata.user, _btcTxnHash, metadata.lockedAmount, metadata.nativeTokenAmount);

        // TODO: Create a function to get the correct MessageFee for the user
        _lzSend(
            _dstEid,
            payload,
            _options,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            _refundAddress
        );

        emit MessageSent(_dstEid, _btcTxnHash, msg.sender, block.timestamp);
    }

    /**
     * @dev Retrieves the PSBT metadata for a given BTC transaction hash.
     * @param _btcTxnHash The BTC transaction hash.
     * @return The PSBT metadata associated with the transaction hash.
     */
    function getPSBTData(bytes32 _btcTxnHash) external view returns (PSBTMetadata memory) {
        return btcTxnHash_psbtMetadata[_btcTxnHash];
    }

    /**
     * @dev Internal function to receive messages from LayerZero.
     * @param _origin The origin of the message.
     * @param _guid The unique identifier for the message.
     * @param _message The message data.
     * @param _executor The address executing the message.
     * @param _extraData Additional data for processing the message.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal virtual override {
        // Implement the receive logic here
        // Validate the origin of the message
        // Validate the message
        // Decode the message
        // Execute the message
        // Emit an event
    }

    /**
     * @dev Pauses the contract in case of emergency.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Withdraws stuck funds from the contract (emergency only).
     */
    function withdraw() external onlyOwner nonReentrant {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert WithdrawalFailed();
    }

    /**
     * @dev Fallback function to receive native tokens.
     */
    fallback() external payable {
        // Fallback function to receive native tokens
    }

    /**
     * @dev Receive function to accept native tokens.
     */
    receive() external payable {
        // Receive native tokens
    }
}
