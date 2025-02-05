// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// TODO: Check if timestamp is needed here as well as baseTokenAmount
struct PSBTMetadata {
    bool isMinted;
    uint32 chainId;
    address user;
    uint256 eBTCAmount;
    uint256 baseTokenAmount; // TODO: Check with Rahul what is this for?
    bytes32 btcTxnHash;
    bytes32 avsPublicKey; // AVS Bitcoin address
    bytes psbtData;
}
// save avsPublicKey/avsNetworkKey

interface IHomeChainCoordinator {
    function sendMessage(uint32 _dstEid, string memory _message, bytes calldata _options) external payable;
}
