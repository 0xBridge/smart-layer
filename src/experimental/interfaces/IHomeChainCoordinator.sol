// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct PSBTMetadata {
    bool isMinted;
    uint32 chainId;
    address user;
    uint256 lockedAmount;
    uint256 nativeTokenAmount;
    bytes32 btcTxnHash;
    bytes32 networkPublicKey; // AVS Bitcoin address
    bytes psbtData;
}

interface IHomeChainCoordinator {
    function sendMessage(uint32 _dstEid, string memory _message, bytes calldata _options) external payable;
}
