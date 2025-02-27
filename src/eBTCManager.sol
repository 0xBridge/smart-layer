// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {eBTC} from "./eBTC.sol";

/**
 * @title eBTCManager
 * @notice Implementation of a secure eBTCManager contract with ownership and pause functionality
 * @dev Manages the minting and burning of eBTC tokens
 */
contract eBTCManager is AccessControl, Pausable, ReentrancyGuard {
    // Errors
    error InvalidRecipient();
    error InvalidAmount();

    // State variables
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    eBTC internal _eBTCToken;

    // Events
    event Minted(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

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
     * @param _baseChainCoordinator Address to grant the minter role to
     * @dev Only callable by accounts with the DEFAULT_ADMIN_ROLE
     */
    function setMinterRole(address _baseChainCoordinator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setupRole(MINTER_ROLE, _baseChainCoordinator);
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
        if (amount == 0) revert InvalidAmount();
        _eBTCToken.mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @notice Burns eBTC tokens
     * @param to Address associated with the burn (for event tracking)
     * @param amount Amount of tokens to burn
     * @dev Only callable by accounts with the MINTER_ROLE
     */
    function burn(address to, uint256 amount) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        _eBTCToken.burn(amount);
        emit Withdrawn(to, amount);
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
}
