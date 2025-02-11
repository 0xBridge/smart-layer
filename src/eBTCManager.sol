// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {eBTC} from "./eBTC.sol";

/**
 * @title eBTCManager
 * @dev Implementation of a secure eBTCManager contract with ownership and pause functionality
 */
contract eBTCManager is AccessControl, Pausable, ReentrancyGuard {
    // Errors
    error InvalidRecipient();
    error InvalidAmount();

    // State variables
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    eBTC private eBTCToken;

    // Events
    event Minted(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @dev Contract constructor
     * @param _initialOwner The address that will own the contract
     */
    constructor(address _initialOwner) {
        // Give baseChainCoordinator access to mint and burn functions
        _setupRole(DEFAULT_ADMIN_ROLE, _initialOwner);
    }

    // Add function to set and remove base chain coordinator address
    function setMinterRole(address _baseChainCoordinator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setupRole(MINTER_ROLE, _baseChainCoordinator);
    }

    // Add function to set and remove eBTC token address
    function setEBTC(address _eBTC) external onlyRole(DEFAULT_ADMIN_ROLE) {
        eBTCToken = eBTC(_eBTC);
    }

    /**
     * @dev Deposits funds into the contract
     * @notice This function is pausable and protected against reentrancy
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        eBTCToken.mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @dev Withdraws funds from the contract
     * @notice This function is pausable and protected against reentrancy
     */
    function burn(address to, uint256 amount) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        eBTCToken.burn(amount);
        emit Withdrawn(to, amount);
    }

    // TODO: Add function to support mint with proofs via other bridge contracts

    /**
     * @dev Pauses all contract operations
     * @notice Only callable by contract owner
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all contract operations
     * @notice Only callable by contract owner
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
