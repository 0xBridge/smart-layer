// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OApp, Origin, MessagingFee, OAppReceiver} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import {TxidCalculator} from "./libraries/TxidCalculator.sol";
import {TxnData, IBaseChainCoordinator, ILayerZeroReceiver} from "./interfaces/IBaseChainCoordinator.sol";
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
    error WithdrawalFailed();
    error InvalidTokenAddress();
    error InvalidPSBTData();
    error InvalidUserOrAmount();
    error InvalidBurnRequest(bytes32 btcTxnHash);
    error InvalidAmount(uint256 minBTCAmount);

    // State variables
    mapping(bytes32 => TxnData) internal _btcTxnHash_txnData;
    eBTCManager internal _eBTCManagerInstance;
    uint32 internal immutable _chainEid;
    uint32 internal immutable _homeEid;

    uint256 public minBTCAmount = 1000; // Min BTC amount / satoshis that needs to be burned
    bytes internal constant OPTIONS = hex"000301001101000000000000000000000000001209c4"; // Options for message sending

    // Events
    event MessageSent(uint32 dstEid, bytes message, bytes32 receiver, uint256 nativeFee);
    event MessageProcessed(
        bytes32 guid, uint32 srcEid, bytes32 sender, address user, bytes32 btcTxnHash, uint256 amount
    );

    /**
     * @notice Initializes the BaseChainCoordinator contract
     * @param endpoint_ Address of the LayerZero endpoint
     * @param owner_ Address of the contract owner
     * @param eBTCManager_ Address of the eBTC manager contract
     * @param chainEid_ The endpoint ID of the current chain
     */
    constructor(address endpoint_, address owner_, address eBTCManager_, uint32 chainEid_, uint32 homeEid_)
        OApp(endpoint_, owner_)
    {
        _transferOwnership(owner_);
        _eBTCManagerInstance = eBTCManager(eBTCManager_);
        _chainEid = chainEid_;
        _homeEid = homeEid_;
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

        (address user, bytes32 btcTxnHash, uint256 amount, uint256 nativeTokenAmount) =
            abi.decode(_message, (address, bytes32, uint256, uint256));

        if (user != address(0) && amount != 0) {
            // 1. Case of mint - Check for replay attacks
            _validateMessageUniqueness(btcTxnHash);
            // 2. Validate message inputs
            _validateInputs(user, amount);
            // 3. Process the message
            _processMessage(btcTxnHash, user, amount);
        } else {
            // 1. Case of burn failure handle - Get the user and amount from the mapping
            TxnData memory txnData = _btcTxnHash_txnData[btcTxnHash];
            user = txnData.user;
            amount = txnData.amount;
            // 2. Delete the request from the mapping
            delete _btcTxnHash_txnData[btcTxnHash];
            // 3. Validate message inputs
            _validateInputs(user, amount);
            // 4. Mint the eBTC tokens back to the user
            _handleMinting(user, amount);
        }

        emit MessageProcessed(_guid, _origin.srcEid, _origin.sender, user, btcTxnHash, amount);
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
     * @notice Validate message inputs
     * @param _user The recipient user address
     * @param _amount The amount of BTC locked
     */
    function _validateInputs(address _user, uint256 _amount) internal pure {
        // Decode the message and process it
        if (_user == address(0) || _amount == 0) {
            revert InvalidUserOrAmount();
        }
    }

    /**
     * @notice Processes a received message
     * @param _btcTxnHash The Bitcoin transaction hash
     * @param _user The recipient user address
     * @param _amount The amount of BTC locked
     * @dev Updates storage and handles minting
     */
    function _processMessage(bytes32 _btcTxnHash, address _user, uint256 _amount) internal {
        // Create the txnData and process it
        TxnData memory txnData = _btcTxnHash_txnData[_btcTxnHash];
        txnData.status = true;
        txnData.user = _user;
        txnData.amount = _amount;
        _btcTxnHash_txnData[_btcTxnHash] = txnData;
        // Additional processing based on message content
        _handleMinting(_user, _amount);
    }

    /**
     * @notice Handles the minting of eBTC tokens
     * @param _user The recipient user address
     * @param _amount The amount to mint
     * @dev Calls the eBTC manager to mint tokens
     */
    function _handleMinting(address _user, uint256 _amount) internal {
        _eBTCManagerInstance.mint(_user, _amount);
    }

    /**
     * @notice Retrieves transaction data for a specific Bitcoin transaction
     * @param _btcTxnHash The Bitcoin transaction hash
     * @return The mint data associated with the transaction
     */
    function getTxnData(bytes32 _btcTxnHash) external view returns (TxnData memory) {
        return _btcTxnHash_txnData[_btcTxnHash];
    }

    /**
     * @notice Checks if a message has been processed
     * @param _btcTxnHash The unique identifier of the message
     * @return True if message has been processed
     */
    function isMessageProcessed(bytes32 _btcTxnHash) public view returns (bool) {
        return _btcTxnHash_txnData[_btcTxnHash].status;
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

    /**
     * @notice Sends a message to the specified chain
     * @param _rawTxn The raw partially signed (not finalized signed) PSBT data for the burn transaction
     * @param _amount The amount of BTC to burn
     * @param _deadline Expiration time for the permit signature
     * @param _v v of the permit signature
     * @param _r r of the permit signature
     * @param _s s of the permit signature
     */
    function burnAndUnlockWithPermit(
        bytes calldata _rawTxn,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable {
        // Tell eBTCManager to burn the eBTC tokens
        address _eBTCToken = _eBTCManagerInstance.getEBTCTokenAddress();
        if (_eBTCToken == address(0)) revert InvalidTokenAddress();
        IERC20 eBTCToken = IERC20(_eBTCToken);
        SafeERC20.safePermit(
            IERC20Permit(address(eBTCToken)), msg.sender, address(this), _amount, _deadline, _v, _r, _s
        );
        SafeERC20.safeTransferFrom(eBTCToken, msg.sender, address(this), _amount);
        SafeERC20.safeApprove(eBTCToken, address(_eBTCManagerInstance), _amount);
        // Call the internal function to burn and unlock
        _burnAndUnlock(_rawTxn, _amount);
    }

    /**
     * @notice Sends a message to the specified chain
     * @param _rawTxn The raw partially signed (not finalized signed) PSBT data for the burn transaction
     * @param _amount The amount of BTC to burn
     */
    function burnAndUnlock(bytes calldata _rawTxn, uint256 _amount) external payable {
        address _eBTCToken = _eBTCManagerInstance.getEBTCTokenAddress();
        if (_eBTCToken == address(0)) revert InvalidTokenAddress();
        IERC20 eBTCToken = IERC20(_eBTCToken);
        SafeERC20.safeTransferFrom(eBTCToken, msg.sender, address(this), _amount);
        SafeERC20.safeApprove(eBTCToken, address(_eBTCManagerInstance), _amount);
        _burnAndUnlock(_rawTxn, _amount);
    }

    /**
     * @notice Burns eBTC tokens and sends a message to the specified chain
     * @param _rawTxn The raw partially signed (not finalized signed) PSBT data for the burn transaction
     * @param _amount The amount of BTC to burn
     */
    function _burnAndUnlock(bytes calldata _rawTxn, uint256 _amount) internal {
        if (_rawTxn.length == 0) revert InvalidPSBTData();
        // Shouldn't allow an already existing PSBT to be sent to HomeChainCoordinator via BaseChainCoordinator
        // bytes32 _btcTxnHash = TxidCalculator.calculateTxid(_rawTxn);
        bytes32 _btcTxnHash = keccak256(_rawTxn);
        if (_btcTxnHash_txnData[_btcTxnHash].user != address(0)) {
            revert InvalidBurnRequest(_btcTxnHash);
        }
        // Burn the requested amount
        _eBTCManagerInstance.burn(_amount);

        // Store the transaction data on BaseChainCoordinator for future reference (No need to save the entire rawTxn)
        _btcTxnHash_txnData[_btcTxnHash] = TxnData({status: true, user: msg.sender, amount: _amount});

        // Pack the amount into _extraData
        bytes memory payload = abi.encode(_amount, msg.sender, _rawTxn);

        // Pass the psbt data to the HomeChainCoordinator in the burn transaction
        _lzSend(
            _homeEid, // HomeChainCoordinator chainEid
            payload,
            OPTIONS,
            MessagingFee(msg.value, 0), // Fee in native gas and ZRO token.
            msg.sender // Refund address in case of failed source message.
        );

        emit MessageSent(_homeEid, _rawTxn, peers[_homeEid], msg.value);
    }

    /**
     * @notice Quotes the gas needed to pay for the full omnichain transaction
     * @param _destChainEid The chainEid of the destination chain
     * @param _payload The payload to be sent to the destination chain, abi encoded amount and rawTxn
     * @param _payInLzToken Boolean for which token to return fee in
     * @return nativeFee Estimated gas fee in native gas
     * @return lzTokenFee Estimated gas fee in ZRO token
     */
    function quote(uint32 _destChainEid, bytes memory _payload, bool _payInLzToken)
        public
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        MessagingFee memory fee = _quote(_destChainEid, _payload, OPTIONS, _payInLzToken);
        return (fee.nativeFee, fee.lzTokenFee);
    }

    /**
     * @notice Receive function to receive native tokens
     */
    receive() external payable {} // This is to receive the fund for the message fee
}
