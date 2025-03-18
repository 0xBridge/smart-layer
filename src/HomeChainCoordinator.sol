// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
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
    error InvalidBlockHash();
    error InvalidAmount(uint256 amount);
    error InvalidSourceOrDestination();
    error InvalidReceiver(address receiver);
    error BitcoinTxnNotFound();
    error BitcoinTxnAndPSBTMismatch();
    error InvalidPeer();
    error WithdrawalFailed();
    error InvalidStatusUpdate();
    error InvalidRequest();

    struct StoreMessageParams {
        bool txnType; // Whether the transaction is a mint or burn
        bytes32 blockHash; // The block hash for the transaction
        bytes32 btcTxnHash; // The BTC transaction hash
        bytes32[] proof; // The proof for the transaction
        uint256 index; // The index of the transaction in the block
        bytes rawTxn; // Raw hex PSBT data for the mint or burn transaction
        bytes32 taprootAddress; // The taproot address for the transaction
        bytes32 networkKey; // The network key for the AVS
        address[] operators; // The operators for the AVS
    }

    // State variables
    BitcoinLightClient internal immutable _lightClient;
    uint32 internal immutable _chainEid;

    address internal _taskManager;
    mapping(bytes32 => PSBTData) internal _btcTxnHash_psbtData;
    mapping(bytes32 => bytes32) internal _taprootAddress_btcTxnHash;

    uint256 public maxGasTokenAmount = 1 ether; // Max amount that can be put as the native token amount
    uint256 public minBTCAmount = 1000; // Min BTC amount / satoshis that needs to be locked

    bytes internal constant OPTIONS = hex"0003010011010000000000000000000000000000c350";

    // Events
    event MessageCreated(bool indexed txnType, bytes32 indexed blockHash, bytes32 indexed btcTxnHash);
    event MessageSent(uint32 indexed dstEid, bytes32 indexed btcTxnHash, address indexed operator, uint256 timestamp);
    event MessageReceived(
        bytes32 indexed guid,
        uint32 srcEid,
        bytes32 indexed sender,
        bytes32 indexed btcTxnHash,
        bool txnType,
        uint256 amount
    );
    event UpdateTxnStatus(bytes32 indexed btcTxnHash, bool status);

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
     * @param _rawHeader The raw block header
     * @param _intermediateHeaders The intermediate headers
     * @param _params The parameters for storing the message
     * @dev Only callable by the contract owner
     */
    function submitBlockAndStoreMessage(
        bytes calldata _rawHeader,
        bytes[] calldata _intermediateHeaders,
        StoreMessageParams calldata _params
    ) external whenNotPaused nonReentrant onlyOwner {
        // 1. Submit block header along with intermediate headers to light client
        bytes32 blockHash = _lightClient.submitRawBlockHeader(_rawHeader, _intermediateHeaders);
        // 2. Validate if the block hash is valid
        if (blockHash != _params.blockHash) revert InvalidPSBTData();
        // 3. Store message with the given BTC transaction hash
        _storeMessage(_params);
    }

    /**
     * @notice Stores a message with the given parameters
     * @param params The parameters for storing the message
     * @dev Only callable by the contract owner
     */
    function storeMessage(StoreMessageParams calldata params) external whenNotPaused nonReentrant onlyOwner {
        _storeMessage(params);
    }

    function _storeMessage(StoreMessageParams memory params) internal {
        bytes32 merkleRoot = _lightClient.getMerkleRootForBlock(params.blockHash);

        PSBTData memory psbtData;
        if (params.txnType) {
            // 1 for mint, 0 for burn
            // 0. Parse PSBT data to get the metadata for the eBTC mint transaction
            BitcoinTxnParser.TransactionMetadata memory metadata = _validatePSBTData(params.rawTxn);
            // 1. Validate input in a separate function call
            _validateInput(merkleRoot, params.btcTxnHash, params.proof, params.index, params.rawTxn, metadata.chainId);
            // 2. Store PSBT data for mint transaction
            psbtData = PSBTData({
                txnType: params.txnType,
                status: false,
                chainId: metadata.chainId,
                user: metadata.receiverAddress,
                rawTxn: params.rawTxn,
                taprootAddress: params.taprootAddress,
                networkKey: params.networkKey,
                operators: params.operators,
                lockedAmount: metadata.lockedAmount,
                nativeTokenAmount: metadata.nativeTokenAmount
            });
            _taprootAddress_btcTxnHash[params.taprootAddress] = params.btcTxnHash;
        } else {
            // 0. Get existing PSBT data for burn transaction
            psbtData = _btcTxnHash_psbtData[params.btcTxnHash];

            // 1. Validate input in a separate function call
            _validateInput(merkleRoot, params.btcTxnHash, params.proof, params.index, params.rawTxn, psbtData.chainId);
            // 2. Update the PSBT data with the required burn transaction details
            psbtData.taprootAddress = params.taprootAddress;
            psbtData.networkKey = params.networkKey;
            psbtData.operators = params.operators;
        }
        _btcTxnHash_psbtData[params.btcTxnHash] = psbtData;
        emit MessageCreated(params.txnType, params.blockHash, params.btcTxnHash);
    }

    // NOTE: The message will come from the endpoint but for now we're considering it to be the owner

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
        _handleMessageSending(chainId, _btcTxnHash, metadata);
    }

    /**
     * @notice Handles the actual message sending logic
     * @param _dstEid The destination chain ID
     * @param _btcTxnHash The Bitcoin transaction hash
     * @param _metadata The transaction metadata
     */
    function _handleMessageSending(
        uint32 _dstEid,
        bytes32 _btcTxnHash,
        BitcoinTxnParser.TransactionMetadata memory _metadata
    ) internal {
        bytes memory payload =
            abi.encode(_metadata.receiverAddress, _btcTxnHash, _metadata.lockedAmount, _metadata.nativeTokenAmount);

        // MessagingReceipt memory messageReceipt;
        if (_dstEid == _chainEid) {
            _handleSameChainMessage(_dstEid, _btcTxnHash, payload);
        } else {
            _handleCrossChainMessage(_dstEid, _btcTxnHash, payload);
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
            Origin(_chainEid, senderAddressInBytes32, 0), _btcTxnHash, _payload, msg.sender, OPTIONS
        );
    }

    /**
     * @notice Handles cross-chain message sending
     */
    function _handleCrossChainMessage(uint32 _dstEid, bytes32 _btcTxnHash, bytes memory _payload)
        internal
        returns (MessagingReceipt memory)
    {
        PSBTData memory psbtData = getPSBTDataForTxnHash(_btcTxnHash);
        psbtData.status = true;
        _btcTxnHash_psbtData[_btcTxnHash] = psbtData; // Update the status of the transaction
        return _lzSend(_dstEid, _payload, OPTIONS, MessagingFee(msg.value, 0), msg.sender);
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
        bytes32[] memory _proof,
        uint256 _index,
        bytes memory _rawTxn,
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

        // 3. Validate txn with SPV data
        if (!BitcoinUtils.verifyTxInclusion(_btcTxnHash, _merkleRoot, _proof, _index)) revert BitcoinTxnNotFound();

        // 4. Validate receiver is set for destination chain
        if (peers[_dstEid] == bytes32(0)) {
            revert InvalidSourceOrDestination();
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
            revert InvalidSourceOrDestination();
        }

        // 3. Check if all the fields needed to be sent in the payload are present in the metadata (should never enter revert ideally)
        if (metadata.chainId == 0 || metadata.user == address(0) || metadata.lockedAmount == 0) {
            revert InvalidPSBTData();
        }

        // 4. Send message through LayerZerobytes memory payload =
        bytes memory payload = abi.encode(metadata.user, _btcTxnHash, metadata.lockedAmount, metadata.nativeTokenAmount);

        _lzSend(
            metadata.chainId,
            payload,
            OPTIONS,
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
        MessagingFee memory fee = _quote(metadata.chainId, payload, OPTIONS, _payInLzToken);
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

    function updateBurnStatus(bytes32 _btcTxnHash) external whenNotPaused onlyOwner {
        // 1. Check if the transaction exists
        PSBTData memory psbtData = _btcTxnHash_psbtData[_btcTxnHash];
        if (psbtData.rawTxn.length == 0) {
            revert InvalidRequest();
        }

        // 2. Update the status of the transaction
        if (psbtData.status) {
            revert InvalidStatusUpdate();
        }
        psbtData.status = true;

        // 3. Update the PSBT data
        _btcTxnHash_psbtData[_btcTxnHash] = psbtData;

        // 4. Emit event for the updated status
        emit UpdateTxnStatus(_btcTxnHash, true);
    }

    /**
     * @notice Internal function to receive messages from LayerZero
     * @param _origin The origin of the message
     * @param _guid The unique identifier for the message
     * @param _message Raw hex PSBT data for the burn transaction
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
        (uint256 amount, bytes memory rawTxn) = abi.decode(_message, (uint256, bytes));
        (BitcoinTxnParser.Input[] memory unlockTxnInputs, BitcoinTxnParser.UnlockTxnData[] memory unlockTxnData) =
            BitcoinTxnParser.extractUnlockOutputs(rawTxn);
        bytes32 mintTxid = unlockTxnInputs[0].txid;
        console.logBytes32(mintTxid);
        bytes32 mintTaprootAddress = _btcTxnHash_psbtData[mintTxid].taprootAddress;
        // Check if the amount being unlocked is less than or equal the eBTC amount burnt
        // TODO: || unlockTxnData[0].amount > amount Put it back with correct mint metadata value
        console.logBytes32(mintTaprootAddress);
        if (unlockTxnData.length == 0 || mintTaprootAddress == bytes32(0)) {
            revert InvalidRequest();
        }

        // 4. Store PSBT data for burn transaction validation
        PSBTData memory psbtData = PSBTData({
            txnType: false, // This is a burn transaction
            status: false, // Transaction is not yet processed
            chainId: _origin.srcEid, // Chain ID of the src chain
            user: address(0), // TODO: Check if makes sense to store the msg.sender on the baseChainCoordinator here
            rawTxn: rawTxn, // Raw hex PSBT data for the burn transaction
            taprootAddress: mintTaprootAddress, // Taproot address for the mint or burn transaction (TODO: Validate at the time of createNewTask for burn)
            networkKey: "", // AVS Bitcoin address
            operators: new address[](0), // Array of operators with whom AVS network key is created
            lockedAmount: unlockTxnData[0].amount, // Amount unlocked in the burn transaction
            nativeTokenAmount: unlockTxnData[1].amount // unlockTxnData[1].amount could be saved as the burn fees
        });

        // 5. Calculate and store the Bitcoin transaction hash
        bytes32 btcTxnHash = TxidCalculator.calculateTxid(rawTxn);
        // Note: User should not be able to manipulate any existing _btcTxnHash_psbtData data (either mint or burn)
        if (_btcTxnHash_psbtData[btcTxnHash].rawTxn.length != 0) {
            revert InvalidRequest();
        }
        _btcTxnHash_psbtData[btcTxnHash] = psbtData;

        // 6. Create task for AVS (can be implemented through a TaskManager contract) - This will be done by the task generator
        emit MessageReceived(
            _guid,
            _origin.srcEid,
            _origin.sender,
            btcTxnHash,
            false, // This is a burn transaction
            unlockTxnData[0].amount
        );
    }

    /**
     * @notice Retrieves the AVS data for a given BTC transaction hash
     * @param _btcTxnHash The BTC transaction hash
     * @return txnType The type of transaction (mint or burn)
     * @return taprootAddress The taproot address for the transaction
     * @return networkKey The network key for the AVS
     * @return operators The operators for the AVS
     */
    function getAVSDataForTxnHash(bytes32 _btcTxnHash) public view returns (bool, bytes32, bytes32, address[] memory) {
        PSBTData memory psbtData = _btcTxnHash_psbtData[_btcTxnHash];
        return (psbtData.txnType, psbtData.taprootAddress, psbtData.networkKey, psbtData.operators);
    }

    /**
     * @notice Retrieves the AVS data for a given taproot address
     * @param _taprootAddress The taproot address
     * @return btcTxnHash The BTC transaction hash
     * @return txnType The type of transaction (mint or burn)
     * @return taprootAddress The taproot address for the transaction
     * @return networkKey The network key for the AVS
     * @return operators The operators for the AVS
     */
    function getAVSDataForTaprootAddress(bytes32 _taprootAddress)
        public
        view
        returns (
            bytes32 btcTxnHash,
            bool txnType,
            bytes32 taprootAddress,
            bytes32 networkKey,
            address[] memory operators
        )
    {
        btcTxnHash = _taprootAddress_btcTxnHash[_taprootAddress];
        (txnType, taprootAddress, networkKey, operators) = getAVSDataForTxnHash(btcTxnHash);
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

    // Create a function to retry for the failure case
    function unlockBurntEBTC(uint32 chainId, bytes32 _btcTxnHash) external payable whenNotPaused nonReentrant {
        // 0. Get the BTC transaction hash from the AVS data
        PSBTData memory psbtData = _btcTxnHash_psbtData[_btcTxnHash];

        // 1. Check if there exists a transaction with the given BTC transaction hash, if it does, it is an invalid request to unlock burnt eBTC
        // if (psbtData.rawTxn.length != 0) {
        //     revert InvalidRequest();
        // }

        // 2. Send message to BaseChainCoordinator to unlock the burnt eBTC
        BitcoinTxnParser.TransactionMetadata memory metadata;
        _handleMessageSending(chainId, _btcTxnHash, metadata);
    }
}
