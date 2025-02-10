// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {eBTC} from "../eBTC.sol";

/**
 * @title eBTCManager
 * @dev Implementation of a secure eBTCManager contract with ownership and pause functionality
 */
contract eBTCManager is Ownable, Pausable, ReentrancyGuard {
    // State variables
    eBTC private eBTCToken;

    // Events
    event Minted(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @dev Contract constructor
     * @param _initialOwner The address that will own the contract
     */
    constructor(address _initialOwner) {
        _transferOwnership(_initialOwner);
    }

    // Add function to set and remove eBTC token address
    function setEBTC(address _eBTC) external onlyOwner {
        eBTCToken = eBTC(_eBTC);
    }

    /**
     * @dev Deposits funds into the contract
     * @notice This function is pausable and protected against reentrancy
     */
    function mint(address to, uint256 amount) external payable onlyOwner nonReentrant whenNotPaused {
        eBTCToken.mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @dev Withdraws funds from the contract
     * @notice This function is pausable and protected against reentrancy
     */
    function withdraw(address to, uint256 amount) external onlyOwner nonReentrant whenNotPaused {
        eBTCToken.burn(amount);
        emit Withdrawn(to, amount);
    }

    // TODO: Add function to support mint with proofs via other bridge contracts

    /**
     * @dev Pauses all contract operations
     * @notice Only callable by contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all contract operations
     * @notice Only callable by contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Prevents accidental ETH transfers to the contract
     */
    receive() external payable {}
}
