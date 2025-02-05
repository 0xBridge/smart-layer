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

/**
 * @title HomeChainCoordinator
 * @dev Contract for coordinating cross-chain messages on the home chain
 */
contract HomeChainCoordinator is OApp, ReentrancyGuard, Pausable {
    // State variables
    address private immutable avsAddress;

    mapping(address => bool) public isOperator; // TODO: Optimise this to store the operators efficiently
    mapping(bytes32 => PSBTMetadata) private btcTxnHash_processedPSBTs; // btcTxnHash => psbtMetadata

    // TODO: Check with Satyam for these values
    uint256 public constant MAX_MINT_AMOUNT = 1000 ether; // Max amount that can be minted
    uint256 public constant MIN_LOCK_AMOUNT = 1000; // Min BTC amount / satoshis that needs to be locked
    uint256 public constant MESSAGE_EXPIRY = 24 hours; // Messages expire after 24 hours

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

    modifier onlyOperator() {
        require(isOperator[msg.sender], "Not an operator");
        _;
    }

    constructor(address _endpoint, address _owner, address[] memory _initialOperators) OApp(_endpoint, _owner) {
        _transferOwnership(_owner);
        _initialiseOperators(_initialOperators);
        // endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    function _initialiseOperators(address[] memory _initialOperators) internal {
        for (uint256 i = 0; i < _initialOperators.length; i++) {
            _setOperator(_initialOperators[i], true);
        }
    }

    function setOperators(address[] calldata _operator, bool[] calldata _statuses) external onlyOwner {
        require(_operator.length == _statuses.length, "Invalid input");
        for (uint256 i = 0; i < _operator.length; i++) {
            _setOperator(_operator[i], _statuses[i]);
        }
    }

    function _setOperator(address _operator, bool _status) internal {
        isOperator[_operator] = _status;
        emit OperatorStatusChanged(_operator, _status);
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

    /**
     * @dev Sends a cross-chain message with PSBT data
     * @param _psbtData The PSBT data to be processed
     * @param _options LayerZero message options
     */
    function sendMessage(bytes32 _btcTxnHash, bytes calldata _psbtData, bytes calldata _options)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        // 0. Operator Authorization
        if (!isOperator[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        // 0. btcTxnHash generated from the psbt data being shared should be the same as the one passed
        bytes32 txid = TxidCalculator.calculateTxid(_psbtData);
        if (txid != _btcTxnHash) {
            revert InvalidPSBTData();
        }

        // TODO: Check if the corrresponding SPV data is present in the SPV contract - why exactly is it needed?
        // TODO: Ensure if the correct witness is present in the psbt data, if not, set it. - But what's the need for this?

        // 1. Parse and validate PSBT data
        BitcoinTxnParser.TransactionMetadata memory metadata = _validatePSBTData(_psbtData);

        // 2. TODO: Get _dstEid for a specific metadata.chainId from LayerZero contract
        uint32 _dstEid = metadata.chainId == 8453 ? 30184 : metadata.chainId;
        console2.log("Destination chain ID: ", _dstEid);

        // 3. Check if the message already exists or is processed
        if (btcTxnHash_processedPSBTs[_btcTxnHash].isMinted) {
            revert TxnAlreadyProcessed(_btcTxnHash);
        }

        // 4. Validate receiver is set for destination chain
        if (peers[_dstEid] == bytes32(0)) {
            revert InvalidReceiver();
        }

        // 5. Validate message expiry?

        // TODO: This needs to come from the metadata itself as this will keep on changing
        bytes32 avsPublicKey;
        // 6. Store PSBT metadata
        PSBTMetadata memory psbtMetaData = PSBTMetadata({
            isMinted: true,
            chainId: metadata.chainId,
            user: metadata.receiverAddress,
            lockedAmount: metadata.lockedAmount,
            nativeTokenAmount: metadata.nativeTokenAmount,
            btcTxnHash: _btcTxnHash,
            avsPublicKey: avsPublicKey,
            psbtData: _psbtData
        });
        btcTxnHash_processedPSBTs[_btcTxnHash] = psbtMetaData;

        // 7. Send message through LayerZerobytes memory payload
        bytes memory payload =
            abi.encode(metadata.chainId, metadata.receiverAddress, metadata.lockedAmount, metadata.nativeTokenAmount);

        // TODO: Create a function to get the correct MessageFee for the user
        _lzSend(
            _dstEid,
            payload,
            _options,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender) // TODO: Check when does the refund happen and how much is refunded | How to know this value in advance?
        );

        emit MessageSent(_dstEid, _btcTxnHash, msg.sender, block.timestamp);
    }

    /**
     * @dev Validates PSBT data and extracts metadata
     */
    function _validatePSBTData(bytes calldata _psbtData)
        internal
        pure
        returns (BitcoinTxnParser.TransactionMetadata memory)
    {
        if (_psbtData.length == 0) {
            revert InvalidPSBTData();
        }

        // Parse transaction outputs and metadata
        bytes memory opReturnData = BitcoinTxnParser.decodeBitcoinTxn(_psbtData);
        BitcoinTxnParser.TransactionMetadata memory metadata = BitcoinTxnParser.decodeMetadata(opReturnData);

        // Validate amounts
        // if (metadata.nativeTokenAmount > MAX_MINT_AMOUNT) {
        //     revert InvalidAmount(metadata.nativeTokenAmount);
        // }
        if (metadata.lockedAmount < MIN_LOCK_AMOUNT) {
            revert InvalidAmount(metadata.lockedAmount);
        }

        // Validate receiver address
        if (metadata.receiverAddress == address(0)) {
            revert InvalidDestination(metadata.receiverAddress);
        }

        return metadata;
    }

    function sendMessageFor(address _receiver, bytes32 _btcTxnHash, bytes calldata _options) external payable {
        if (btcTxnHash_processedPSBTs[_btcTxnHash].user != _receiver) {
            revert InvalidReceiver(); // This also ensures that the txn is already present
        }

        PSBTMetadata memory psbtMetaData = btcTxnHash_processedPSBTs[_btcTxnHash];
        // 1. Parse and get metadata from psbtMetaData

        // 2. TODO: Get _dstEid for a specific metadata.chainId from LayerZero contract
        uint32 _dstEid = psbtMetaData.chainId == 8453 ? 30184 : psbtMetaData.chainId;

        // 3. Validate receiver is set for destination chain
        if (peers[_dstEid] == bytes32(0)) {
            revert InvalidReceiver();
        }

        // 4. TODO: Check if all the fields needed to be sent in the payload are present in the metadata

        // 5. Send message through LayerZerobytes memory payload =
        bytes memory payload = abi.encode(
            psbtMetaData.chainId, psbtMetaData.user, psbtMetaData.lockedAmount, psbtMetaData.nativeTokenAmount
        );

        // TODO: Create a function to get the correct MessageFee for the user
        _lzSend(
            _dstEid,
            payload,
            _options,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender) // TODO: Check when does the refund happen and how much is refunded | How to know this value in advance?
        );

        emit MessageSent(_dstEid, _btcTxnHash, msg.sender, block.timestamp);
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
