// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {eBTC} from "../../src/eBTC.sol";

// Mock V2 implementation for testing upgrades
contract eBTCV2 is eBTC {
    uint256 public newVariable;

    function setNewVariable(uint256 _value) external {
        newVariable = _value;
    }

    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}

// Helper Contracts for Testing
contract MockNonUUPS {
    function initialize(address) external {}
}

contract ReentrantUpgrader {
    eBTC private immutable proxy;

    constructor(eBTC _proxy) {
        proxy = _proxy;
    }

    // Attempting to trigger reentrancy during upgrade
    fallback() external payable {
        proxy.upgradeTo(address(this));
    }
}
