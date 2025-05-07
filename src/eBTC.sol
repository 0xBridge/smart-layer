// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Upgradeable} from "@openzeppelin-upgrades/contracts/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgrades/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin-upgrades/contracts/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

/**
 * @title eBTC Token
 * @notice ERC20 token representing Bitcoin on other chains
 * @dev Upgradeable token with minting, burning, and permit capabilities
 */
contract eBTC is
    UUPSUpgradeable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice Constructor that disables initializers
     * @dev This prevents the implementation contract from being initialized
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the eBTC token
     * @param minter_ Address that will have minting privileges
     * @dev Can only be called once due to initializer modifier
     */
    function initialize(address minter_) public initializer {
        __ERC20_init("Extended Bitcoin Token", "eBTC");
        __ERC20Burnable_init();
        __AccessControl_init();
        __ERC20Permit_init("Extended Bitcoin Token");
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, minter_);
    }

    /**
     * @notice Returns the number of decimals used for the token
     * @return The number of decimals (8 to match Bitcoin)
     * @dev Overrides the default ERC20 18 decimals
     */
    function decimals() public view virtual override returns (uint8) {
        return 8;
    }

    /**
     * @notice Mints new tokens
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * @dev Only callable by accounts with the MINTER_ROLE
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Hook that is called before any token transfer
     * @param from The sender address
     * @param to The recipient address
     * @param amount The amount of tokens to transfer
     * @dev Calls the ERC20 implementation of _beforeTokenTransfer
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @notice Burns tokens from the caller
     * @param amount Amount of tokens to burn
     * @dev Overrides ERC20Burnable's burn to restrict to MINTER_ROLE
     */
    function burn(uint256 amount) public override onlyRole(MINTER_ROLE) {
        super.burn(amount);
    }

    /**
     * @notice Authorizes an upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     * @dev Only callable by accounts with the DEFAULT_ADMIN_ROLE
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
