// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMailbox {
    function dispatch(uint32 _destinationDomain, bytes32 _recipientAddress, bytes calldata _messageBody)
        external
        returns (bytes32);
}

contract VulnerableContract {
    uint256 public value;
    IMailbox public constant mailbox = IMailbox(0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70);

    /// @dev this contract is vulnerable here, it doesn't validate the actual sender
    function handle(uint32, bytes32, bytes calldata _message) external {
        require(msg.sender == address(mailbox));
        value = abi.decode(_message, (uint256));
    }
}
