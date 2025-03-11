// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {BitcoinTxnParser} from "./libraries/BitcoinTxnParser.sol";
import {TxidCalculator} from "./libraries/TxidCalculator.sol";
import {BitcoinUtils} from "./libraries/BitcoinUtils.sol";
import {BitcoinLightClient} from "./BitcoinLightClient.sol";
import {PSBTData, IHomeChainCoordinator} from "./interfaces/IHomeChainCoordinator.sol";
import {Origin, IBaseChainCoordinator} from "./interfaces/IBaseChainCoordinator.sol";

/**
 * @title HomeChainCoordinator
 * @notice Contract for coordinating cross-chain messages on the home chain
 * @dev Handles verification and cross-chain messaging for Bitcoin transactions
 */
contract HomeChainCoordinator is OApp, ReentrancyGuard, Pausable, IHomeChainCoordinator {
    // Errors
    error TxnAlreadyProcessed(bytes32 btcTxnHash);
    error InvalidPSBTData();
    error InvalidAmount(uint256 amount);
    error InvalidDestination();
    error InvalidReceiver(address receiver);
    error BitcoinTxnNotFound();
    error BitcoinTxnAndPSBTMismatch();
    error InvalidPeer();
    error WithdrawalFailed();

    // Added struct to reduce stack depth
    struct BlockSubmissionParams {
        bytes rawHeader;
        bytes[] intermediateHeaders;
        bytes32 btcTxnHash;
        bytes32[] proof;
        uint256 index;
        bytes rawTxn;
        string taprootAddress;
        string networkKey;
        address[] operators;
    }

    // State variables
    BitcoinLightClient internal immutable _lightClient;
    uint32 internal immutable _chainEid;

    address internal _taskManager;
    mapping(bytes32 => PSBTData) internal _btcTxnHash_psbtData;

    uint256 public maxGasTokenAmount = 1 ether; // Max amount that can be put as the native token amount
    uint256 public minBTCAmount = 1000; // Min BTC amount / satoshis that needs to be locked

    bytes internal constant _options = hex"0003010011010000000000000000000000000000c350"; // TODO: Get rid of this

    // Events
    event MessageSent(uint32 indexed dstEid, bytes32 indexed psbtHash, address indexed operator, uint256 timestamp);
    event MessageCreated(bool indexed isMint, bytes32 indexed blockHash, bytes32 indexed btcTxnHash);
    event MessageReceived(
        bytes32 indexed guid,
        uint32 srcEid,
        bytes32 sender,
        bytes32 indexed btcTxnHash,
        address indexed receiver,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @notice Initializes the HomeChainCoordinator contract
     * @param lightClient_ Address of the Bitcoin light client
     * @param endpoint_ Address of the LayerZero endpoint
     * @param owner_ Address of the contract owner
     * @param chainEid_ The endpoint ID of the current chain
     */
    constructor(address lightClient_, address endpoint_, address owner_, uint32 chainEid_) OApp(endpoint_, owner_) {
        _transferOwnership(owner_);
        _lightClient = BitcoinLightClient(lightClient_);
        _chainEid = chainEid_;
    }

    /**
     * @notice Sets the maximum amount of gas tokens that can be used
     * @param _maxGasTokenAmount The maximum gas token amount to set
     * @dev Only callable by the contract owner
     */
    function setMaxGasTokenAmount(uint256 _maxGasTokenAmount) external onlyOwner {
        if (_maxGasTokenAmount == 0) revert InvalidAmount(_maxGasTokenAmount);
        maxGasTokenAmount = _maxGasTokenAmount;
    }

    /**
     * @notice Sets the minimum amount of BTC that needs to be locked
     * @param _minBtcAmount The minimum BTC amount to set
     * @dev Only callable by the contract owner
     */
    function setMinBtcAmount(uint256 _minBtcAmount) external onlyOwner {
        if (_minBtcAmount == 0) revert InvalidAmount(_minBtcAmount);
        minBTCAmount = _minBtcAmount;
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
     * @notice Submits a block and sends a message with PSBT data
     * @param _isMint Whether the transaction is a mint or burn
     * @param params Struct containing all the parameters to avoid stack too deep error
     * @dev Only callable by the contract owner
     */
    function submitBlockAndStoreMessage(bool _isMint, BlockSubmissionParams calldata params)
        external
        whenNotPaused
        nonReentrant
        onlyOwner
    {
        // 0. Submit block header along with intermediate headers to light client
        bytes32 blockHash = _lightClient.submitRawBlockHeader(params.rawHeader, params.intermediateHeaders);
        // 2. Store message with the given BTC transaction hash
        _storeMessage(
            _isMint,
            blockHash,
            params.btcTxnHash,
            params.proof,
            params.index,
            params.rawTxn,
            params.taprootAddress,
            params.networkKey,
            params.operators
        );
    }

    /**
     * @notice Stores a cross-chain message for a given BTC transaction hash
     * @param _isMint Whether the transaction is a mint or burn
     * @param _blockHash The block hash to validate the transaction
     * @param _btcTxnHash The BTC transaction hash
     * @param _proof The proof for the transaction
     * @param _index The index of the transaction in the block
     * @param _rawTxn The PSBT data to be processed
     * @param _taprootAddress The taproot address where the funds are locked or unlocked from
     * @param _networkKey The network public key for the AVS
     * @param _operators Array of operators with whom AVS network key is created
     * @dev Only callable by the contract owner
     */
    function storeMessage(
        bool _isMint,
        bytes32 _blockHash,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _rawTxn,
        string calldata _taprootAddress,
        string calldata _networkKey,
        address[] calldata _operators
    ) external whenNotPaused nonReentrant onlyOwner {
        _storeMessage(
            _isMint, _blockHash, _btcTxnHash, _proof, _index, _rawTxn, _taprootAddress, _networkKey, _operators
        );
    }

    function _storeMessage(
        bool _isMint,
        bytes32 _blockHash,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _rawTxn,
        string calldata _taprootAddress,
        string calldata _networkKey,
        address[] calldata _operators
    ) internal {
        bytes32 merkleRoot = _lightClient.getMerkleRootForBlock(_blockHash);
        // 0. Parse and validate PSBT data
        BitcoinTxnParser.TransactionMetadata memory metadata = _validatePSBTData(_rawTxn);
        // 1. Validate input in a separate function call
        _validateInput(merkleRoot, _btcTxnHash, _proof, _index, _rawTxn, metadata.chainId);
        // 2. Store PSBT data for mint/burn transaction validation
        PSBTData memory psbtData = PSBTData({
            txnType: _isMint,
            status: false,
            chainId: metadata.chainId,
            user: metadata.receiverAddress,
            rawTxn: _rawTxn,
            taprootAddress: _taprootAddress,
            networkKey: _networkKey,
            operators: _operators,
            lockedAmount: metadata.lockedAmount,
            nativeTokenAmount: metadata.nativeTokenAmount
        });
        _btcTxnHash_psbtData[_btcTxnHash] = psbtData;
        emit MessageCreated(_isMint, _blockHash, _btcTxnHash);
    }

    // TODO: The message will come from the endpoint but for now we're considering it to be the owner
    // TODO: Check if the message is coming from the task manager

    /**
     * @notice Function to send a cross-chain message of the given BTC transaction hash
     * @param _btcTxnHash The BTC transaction hash
     * @dev Validates the PSBT data and sends the message through LayerZero
     */
    function sendMessage(bytes32 _btcTxnHash) external payable whenNotPaused nonReentrant onlyOwner {
        // 0. Parse transaction outputs and metadata
        uint32 chainId = _btcTxnHash_psbtData[_btcTxnHash].chainId;
        // 1. Get the metadata as well as other fields required for the message
        PSBTData memory psbtData = getPSBTDataForTxnHash(_btcTxnHash);
        // 2. Get the metadata
        bytes memory opReturnData = BitcoinTxnParser.decodeBitcoinTxn(psbtData.rawTxn);
        BitcoinTxnParser.TransactionMetadata memory metadata = BitcoinTxnParser.decodeMetadata(opReturnData);
        // 3. Handle message sending in a separate function
        _handleMessageSending(
            psbtData.txnType,
            chainId,
            _btcTxnHash,
            metadata,
            psbtData.taprootAddress,
            psbtData.networkKey,
            psbtData.operators
        );
    }

    /**
     * @notice Handles the actual message sending logic
     * @param _isMint Whether the transaction is a mint or burn
     * @param _dstEid The destination chain ID
     * @param _btcTxnHash The Bitcoin transaction hash
     * @param _metadata The transaction metadata
     * @param _taprootAddress The taproot address where the funds are locked or unlocked from
     * @param _networkKey The network public key for the AVS
     * @param _operators // Array of operators with whom AVS network key is created
     */
    function _handleMessageSending(
        bool _isMint,
        uint32 _dstEid,
        bytes32 _btcTxnHash,
        BitcoinTxnParser.TransactionMetadata memory _metadata,
        string memory _taprootAddress,
        string memory _networkKey,
        address[] memory _operators
    ) internal {
        bytes memory payload =
            abi.encode(_metadata.receiverAddress, _btcTxnHash, _metadata.lockedAmount, _metadata.nativeTokenAmount);

        if (_dstEid == _chainEid) {
            _handleSameChainMessage(_dstEid, _btcTxnHash, payload);
        } else {
            _handleCrossChainMessage(
                _isMint, _dstEid, _btcTxnHash, _metadata, payload, _taprootAddress, _networkKey, _operators
            );
        }
        emit MessageSent(_dstEid, _btcTxnHash, msg.sender, block.timestamp);
    }

    /**
     * @notice Handles message sending within the same chain
     */
    function _handleSameChainMessage(uint32 _dstEid, bytes32 _btcTxnHash, bytes memory _payload) internal {
        address baseChainCoordinator = address(uint160(uint256(peers[_dstEid])));
        bytes32 senderAddressInBytes32 = bytes32(uint256(uint160(address(this))));
        IBaseChainCoordinator(baseChainCoordinator).lzReceive(
            Origin(_chainEid, senderAddressInBytes32, 0), _btcTxnHash, _payload, msg.sender, _options
        );
    }

    /**
     * @notice Handles cross-chain message sending
     */
    function _handleCrossChainMessage(
        bool _isMint,
        uint32 _dstEid,
        bytes32 _btcTxnHash,
        BitcoinTxnParser.TransactionMetadata memory _metadata,
        bytes memory _payload,
        string memory _taprootAddress,
        string memory _networkKey,
        address[] memory _operators
    ) internal {
        PSBTData memory psbtData = getPSBTDataForTxnHash(_btcTxnHash);
        psbtData.status = true;
        _btcTxnHash_psbtData[_btcTxnHash] = psbtData; // Update the status of the transaction
        _lzSend(_dstEid, _payload, _options, MessagingFee(msg.value, 0), msg.sender);
    }

    /**
     * @notice Validates input parameters for message sending
     * @param _merkleRoot The merkle root for the block
     * @param _btcTxnHash The BTC transaction hash
     * @param _proof The proof for the transaction
     * @param _index The index of the transaction in the block
     * @param _rawTxn // Raw hex PSBT data for the mint or burn transaction
     * @param _dstEid The destination chain endpoint ID
     * @dev Verifies transaction existence and validity
     */
    function _validateInput(
        bytes32 _merkleRoot,
        bytes32 _btcTxnHash,
        bytes32[] calldata _proof,
        uint256 _index,
        bytes calldata _rawTxn,
        uint32 _dstEid
    ) internal view {
        // 1. btcTxnHash generated from the psbt data being shared should be the same as the one passed
        bytes32 txid = TxidCalculator.calculateTxid(_rawTxn);
        if (txid != _btcTxnHash) {
            revert BitcoinTxnAndPSBTMismatch();
        }

        // 2. Check if the message already exists or is processed
        if (_btcTxnHash_psbtData[_btcTxnHash].status) {
            revert TxnAlreadyProcessed(_btcTxnHash);
        }

        // 3. Validate txn with SPV data (TODO: Uncomment this when the backend service to publish SPV blocks is ready by Rahul)
        if (!BitcoinUtils.verifyTxInclusion(_btcTxnHash, _merkleRoot, _proof, _index)) revert BitcoinTxnNotFound();

        // 4. Validate receiver is set for destination chain
        if (peers[_dstEid] == bytes32(0)) {
            revert InvalidDestination();
        }
    }

    /**
     * @notice Validates PSBT data and extracts metadata
     * @param _rawTxn // Raw hex PSBT data for the mint or burn transaction
     * @return metadata The extracted transaction metadata
     * @dev Checks for valid amounts and receiver address
     */
    function _validatePSBTData(bytes memory _rawTxn)
        internal
        view
        returns (BitcoinTxnParser.TransactionMetadata memory)
    {
        if (_rawTxn.length == 0) {
            revert InvalidPSBTData();
        }

        // Parse transaction outputs and metadata
        bytes memory opReturnData = BitcoinTxnParser.decodeBitcoinTxn(_rawTxn);
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
            revert InvalidReceiver(metadata.receiverAddress);
        }

        return metadata;
    }

    /**
     * @notice Sends a message for a specific receiver with the given BTC transaction hash
     * @param _receiver The address of the receiver
     * @param _btcTxnHash The BTC transaction hash
     * @dev Payable function to cover cross-chain message fees
     */
    function sendMessageFor(address _receiver, bytes32 _btcTxnHash) external payable {
        if (_btcTxnHash_psbtData[_btcTxnHash].user != _receiver) {
            revert InvalidReceiver(_receiver); // This also ensures that the txn is already present
        }

        // 1. Parse and get metadata from psbtData
        PSBTData memory metadata = _btcTxnHash_psbtData[_btcTxnHash];

        // 2. Validate receiver is set for destination chain
        if (peers[metadata.chainId] == bytes32(0)) {
            revert InvalidDestination();
        }

        // 3. Check if all the fields needed to be sent in the payload are present in the metadata (should never enter revert ideally)
        if (metadata.chainId == 0 || metadata.user == address(0) || metadata.lockedAmount == 0) {
            revert InvalidPSBTData();
        }

        // 4. Send message through LayerZerobytes memory payload =
        bytes memory payload = abi.encode(metadata.user, _btcTxnHash, metadata.lockedAmount, metadata.nativeTokenAmount);

        // TODO: Create a function to get the correct MessageFee for the user
        _lzSend(
            metadata.chainId,
            payload,
            _options,
            MessagingFee(msg.value, 0), // Fee in native gas and ZRO token.
            msg.sender // Refund address in case of failed source message.
        );

        emit MessageSent(metadata.chainId, _btcTxnHash, msg.sender, block.timestamp);
    }

    /**
     * @notice Quotes the gas needed to pay for the full omnichain transaction
     * @param _btcTxnHash The BTC transaction hash
     * @param _rawTxn // Raw hex PSBT data for the mint or burn transaction
     * @param _payInLzToken Boolean for which token to return fee in
     * @return nativeFee Estimated gas fee in native gas
     * @return lzTokenFee Estimated gas fee in ZRO token
     */
    function quote(bytes32 _btcTxnHash, bytes memory _rawTxn, bool _payInLzToken)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        bytes memory opReturnData = BitcoinTxnParser.decodeBitcoinTxn(_rawTxn);
        BitcoinTxnParser.TransactionMetadata memory metadata = BitcoinTxnParser.decodeMetadata(opReturnData);
        bytes memory payload =
            abi.encode(metadata.receiverAddress, _btcTxnHash, metadata.lockedAmount, metadata.nativeTokenAmount);
        MessagingFee memory fee = _quote(metadata.chainId, payload, _options, _payInLzToken);
        return (fee.nativeFee, fee.lzTokenFee);
    }

    /**
     * @notice Retrieves the PSBT metadata for a given BTC transaction hash
     * @param _btcTxnHash The BTC transaction hash
     * @return The PSBT metadata associated with the transaction hash
     */
    function getPSBTDataForTxnHash(bytes32 _btcTxnHash) public view returns (PSBTData memory) {
        return _btcTxnHash_psbtData[_btcTxnHash];
    }

    /**
     * @notice Internal function to receive messages from LayerZero
     * @param _origin The origin of the message
     * @param _guid The unique identifier for the message
     * @param _message The message data
     * @param _executor The address executing the message
     * @param _extraData Additional data for processing the message
     * @dev Empty implementation as this contract doesn't receive LayerZero messages
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal virtual override whenNotPaused {
        // 1. Validate the origin of the message
        if (peers[_origin.srcEid] != _origin.sender) {
            revert InvalidPeer();
        }

        // 2. Validate and decode the PSBT data
        if (_message.length == 0) {
            revert InvalidPSBTData();
        }

        // 3. Parse psbt and get eBTC burn amount, taproot address, network key, and receiver BTC address

        // 4. Store PSBT data for burn transaction validation
        // PSBTData memory psbtData = PSBTData({
        //     status: false, // This is a burn transaction
        //     chainId: metadata.chainId,
        //     user: metadata.receiverAddress,
        //     lockedAmount: metadata.lockedAmount,
        //     nativeTokenAmount: metadata.nativeTokenAmount,
        //     networkKey: metadata.networkKey, // Network key for burn validation
        //     psbtData: _message
        // });

        // 5. Calculate and store the Bitcoin transaction hash
        // bytes32 btcTxnHash = TxidCalculator.calculateTxid(_message);
        // _btcTxnHash_psbtData[btcTxnHash] = psbtData;

        // 6. Create task for AVS (can be implemented through a TaskManager contract) - This will be done by the task generator
        // emit MessageReceived(
        //     _guid,
        //     _origin.srcEid,
        //     _origin.sender,
        //     btcTxnHash,
        //     metadata.receiverAddress,
        //     metadata.lockedAmount,
        //     block.timestamp
        // );
    }

    /**
     * @notice Retrieves the AVS data for a given BTC transaction hash
     * @param _btcTxnHash The BTC transaction hash
     * @return txnType The type of transaction (mint or burn)
     * @return taprootAddress The taproot address for the transaction
     * @return networkKey The network key for the AVS
     * @return operators The operators for the AVS
     */
    function getAVSDataForTxnHash(bytes32 _btcTxnHash)
        external
        view
        returns (bool, string memory, string memory, address[] memory)
    {
        PSBTData memory psbtData = _btcTxnHash_psbtData[_btcTxnHash];
        return (psbtData.txnType, psbtData.taprootAddress, psbtData.networkKey, psbtData.operators);
    }

    /**
     * @notice Pauses the contract in case of emergency
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
