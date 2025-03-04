// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {BaseChainCoordinator} from "./BaseChainCoordinator.sol";
import {eBTC} from "./eBTC.sol";

/**
 * @title eBTCManager
 * @notice Implementation of a secure eBTCManager contract with ownership and pause functionality
 * @dev Manages the minting and burning of eBTC tokens
 */
contract eBTCManager is AccessControl, Pausable, ReentrancyGuard {
    using SafeTransferLib for address;
    // Errors

    error InvalidRecipient();
    error InvalidAmount(uint256 amount);

    // State variables
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    BaseChainCoordinator internal _baseChainCoordinator;
    eBTC internal _eBTCToken;

    uint256 public minBTCAmount = 1000; // Min BTC amount / satoshis that needs to be locked

    // Events
    event Minted(address indexed user, uint256 amount);
    event Burn(address indexed user, uint256 amount);

    /**
     * @notice Initializes the eBTCManager contract
     * @param initialOwner_ The address that will own the contract
     * @dev Sets up initial access control roles
     */
    constructor(address initialOwner_) {
        // Give baseChainCoordinator access to mint and burn functions
        _setupRole(DEFAULT_ADMIN_ROLE, initialOwner_);
    }

    /**
     * @notice Sets the minter role for a contract
     * @param baseChainCoordinator Address to grant the minter role to
     * @dev Only callable by accounts with the DEFAULT_ADMIN_ROLE
     */
    function setBaseChainCoordinator(address baseChainCoordinator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // TODO: Register baseChainCoordinator contract instance here so that it can be called to pass the message of burn
        _setupRole(MINTER_ROLE, baseChainCoordinator);
        _baseChainCoordinator = BaseChainCoordinator(baseChainCoordinator);
    }

    /**
     * @notice Sets the eBTC token contract address
     * @param _eBTC Address of the eBTC token contract
     * @dev Only callable by accounts with the DEFAULT_ADMIN_ROLE
     */
    function setEBTC(address _eBTC) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _eBTCToken = eBTC(_eBTC);
    }

    /**
     * @notice Mints eBTC tokens to a recipient
     * @param to Address of the recipient
     * @param amount Amount of tokens to mint
     * @dev Only callable by accounts with the MINTER_ROLE
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount(amount);
        _eBTCToken.mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @notice Burns eBTC tokens
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external nonReentrant whenNotPaused {
        // address(_eBTCToken).safeTransferFrom(msg.sender, address(this), amount);
        _burn(amount);
    }

    /**
     * @notice Burns eBTC tokens
     * @param amount Amount of tokens to burn
     */
    function _burn(uint256 amount) internal {
        if (amount < minBTCAmount) revert InvalidAmount(amount);
        _eBTCToken.burn(amount);
        emit Burn(msg.sender, amount);
    }

    // TODO: Add function to support mint with proofs via other bridge contracts

    /**
     * @notice Pauses all contract operations
     * @dev Only callable by accounts with the DEFAULT_ADMIN_ROLE
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses all contract operations
     * @dev Only callable by accounts with the DEFAULT_ADMIN_ROLE
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Sets the minimum amount of BTC that needs to be locked
     * @param _minBtcAmount The minimum BTC amount to set
     * @dev Only callable by the contract owner
     */
    function setMinBtcAmount(uint256 _minBtcAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minBtcAmount == 0) revert InvalidAmount(_minBtcAmount);
        minBTCAmount = _minBtcAmount;
    }

    /**
     * @notice Get eBTC token contract address
     */
    function getEBTCTokenAddress() external view returns (address) {
        return address(_eBTCToken);
    }
}
