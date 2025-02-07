// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
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
    // State variables
    BitcoinLightClient private lightClient;

    address private taskManager;
    mapping(bytes32 => PSBTMetadata) private btcTxnHash_psbtMetadata;

    uint256 public maxGasTokenAmount = 1 ether; // Max amount that can be put as the native token amount
    uint256 public minBTCAmount = 1000; // Min BTC amount / satoshis that needs to be locked

    // Events
    event MessageSent(uint32 indexed dstEid, bytes32 indexed psbtHash, address indexed operator, uint256 timestamp);
    event OperatorStatusChanged(address indexed operator, bool status);

    // Errors
    error UnauthorizedOperator(address operator);
    error PSBTAlreadyProcessed(bytes32 psbtHash);
    error TxnAlreadyProcessed(bytes32 btcTxnHash);
    error InvalidPSBTData();
    error UnsupportedChain(uint32 chainId);
    error InvalidAmount(uint256 amount);
    error MessageExpired();
    error InvalidDestination(address receiver);
    error InvalidReceiver();
    error InvalidBitcoinTxn();

    modifier onlyTaskManager() {
        require(msg.sender == taskManager, UnauthorizedOperator(msg.sender));
        _;
    }

    constructor(address _lightClient, address _endpoint, address _owner, address _taskManager)
        OApp(_endpoint, _owner)
    {
        _transferOwnership(_owner);
        lightClient = BitcoinLightClient(_lightClient);
        taskManager = _taskManager;
        // endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    // Create getters and setters for the below values
    function setMaxGasTokenAmount(uint256 _maxGasTokenAmount) external onlyOwner {
        require(_maxGasTokenAmount > 0, "Invalid amount");
        maxGasTokenAmount = _maxGasTokenAmount;
    }

    function setMinBtcAmount(uint256 _minBtcAmount) external onlyOwner {
        require(_minBtcAmount > 0, "Invalid amount");
        minBTCAmount = _minBtcAmount;
    }

    /**
     * @dev Sets the peer address for a specific chain _dstEid
     * @param _dstEid The endpoint ID of the destination chain
     * @param _peer The receiver address on the destination chain
     */
    function setPeer(uint32 _dstEid, bytes32 _peer) public override onlyOwner {
        require(_peer != bytes32(0), "Invalid peer");
        super.setPeer(_dstEid, _peer);
    }

    function submitBlockAndSendMessage(
        bytes calldata rawHeader,
        bytes[] calldata intermediateHeaders,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _psbtData,
        bytes calldata _options,
        address refundAddress
    ) external payable whenNotPaused nonReentrant onlyTaskManager {
        // 0. Submit block
        bytes32 blockHash = lightClient.submitRawBlockHeader(rawHeader, intermediateHeaders);
        // 1. Get merkle root
        bytes32 merkleRoot = lightClient.getMerkleRootForBlock(blockHash);
        // 2. Send message
        _sendMessage(blockHash, _btcTxnHash, merkleRoot, _proof, _index, _psbtData, _options, refundAddress);
    }

    /**
     * @dev Sends a cross-chain message with PSBT data
     * @param _psbtData The PSBT data to be processed
     * @param _options LayerZero message options
     */
    function sendMessage(
        bytes32 _blockHash,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _psbtData,
        bytes calldata _options,
        address refundAddress
    ) external payable whenNotPaused nonReentrant onlyTaskManager {
        bytes32 merkleRoot = lightClient.getMerkleRootForBlock(_blockHash);
        _sendMessage(_blockHash, _btcTxnHash, merkleRoot, _proof, _index, _psbtData, _options, refundAddress);
    }

    /**
     * @dev Sends a cross-chain message with PSBT data
     * @param _psbtData The PSBT data to be processed
     * @param _options LayerZero message options
     */
    function _sendMessage(
        bytes32 _blockHash,
        bytes32 _btcTxnHash,
        bytes32 _merkleRoot,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _psbtData,
        bytes calldata _options,
        address refundAddress
    ) internal {
        // 0. btcTxnHash generated from the psbt data being shared should be the same as the one passed
        bytes32 txid = TxidCalculator.calculateTxid(_psbtData);
        if (txid != _btcTxnHash) {
            revert InvalidPSBTData();
        }

        // TODO: Check if the corrresponding SPV data is present in the SPV contract - why exactly is it needed though?

        // 1. Parse and validate PSBT data
        BitcoinTxnParser.TransactionMetadata memory metadata = _validatePSBTData(_psbtData);

        // 2. TODO: Get _dstEid for a specific metadata.chainId from LayerZero contract
        uint32 _dstEid = metadata.chainId == 8453 ? 30184 : metadata.chainId;
        console2.log("Destination chain ID: ", _dstEid);

        // 3. Check if the message already exists or is processed
        if (btcTxnHash_psbtMetadata[_btcTxnHash].isMinted) {
            revert TxnAlreadyProcessed(_btcTxnHash);
        }

        // 4. Validate receiver is set for destination chain
        if (peers[_dstEid] == bytes32(0)) {
            revert InvalidReceiver();
        }

        // 5. Validate txn with SPV data
        require(BitcoinUtils.verifyTxInclusion(_btcTxnHash, _merkleRoot, _proof, _index), InvalidBitcoinTxn());

        // TODO: This needs to come from the metadata itself as this will keep on changing
        bytes32 networkPublicKey;
        // 6. Store PSBT metadata
        PSBTMetadata memory psbtMetaData = PSBTMetadata({
            isMinted: true,
            chainId: metadata.chainId,
            user: metadata.receiverAddress,
            lockedAmount: metadata.lockedAmount,
            nativeTokenAmount: metadata.nativeTokenAmount,
            btcTxnHash: _btcTxnHash,
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
            refundAddress
        );

        emit MessageSent(_dstEid, _btcTxnHash, msg.sender, block.timestamp);
    }

    /**
     * @dev Validates PSBT data and extracts metadata
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
        // if (metadata.nativeTokenAmount > maxGasTokenAmount) {
        //     revert InvalidAmount(metadata.nativeTokenAmount);
        // }
        if (metadata.lockedAmount < minBTCAmount) {
            revert InvalidAmount(metadata.lockedAmount);
        }

        // Validate receiver address
        if (metadata.receiverAddress == address(0)) {
            revert InvalidDestination(metadata.receiverAddress);
        }

        return metadata;
    }

    function sendMessageFor(address _receiver, bytes32 _btcTxnHash, bytes calldata _options, address refundAddress)
        external
        payable
    {
        if (btcTxnHash_psbtMetadata[_btcTxnHash].user != _receiver) {
            revert InvalidReceiver(); // This also ensures that the txn is already present
        }

        PSBTMetadata memory metadata = btcTxnHash_psbtMetadata[_btcTxnHash];
        // 1. Parse and get metadata from psbtMetaData

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
            refundAddress
        );

        emit MessageSent(_dstEid, _btcTxnHash, msg.sender, block.timestamp);
    }

    function getPSBTData(bytes32 _btcTxnHash) external view returns (PSBTMetadata memory) {
        return btcTxnHash_psbtMetadata[_btcTxnHash];
    }

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
        require(success, "Withdrawal failed");
    }

    fallback() external payable {
        // Fallback function to receive native tokens
    }

    receive() external payable {
        // Receive native tokens
    }
}
