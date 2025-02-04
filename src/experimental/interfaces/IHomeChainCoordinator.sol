// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// TODO: Check if timestamp is needed here as well as baseTokenAmount
struct PSBTMetadata {
    bool isMinted;
    uint32 chainId;
    address user;
    uint256 eBTCAmount;
    uint256 baseTokenAmount;
    bytes32 btcTxnHash;
    bytes psbtData;
}

interface IHomeChainCoordinator {
    function sendMessage(uint32 _dstEid, string memory _message, bytes calldata _options) external payable;
}
