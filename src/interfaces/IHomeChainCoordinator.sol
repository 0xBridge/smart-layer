// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct PSBTMetadata {
    bool isMinted;
    uint32 chainId;
    address user;
    uint256 lockedAmount;
    uint256 nativeTokenAmount;
    bytes32 networkPublicKey; // AVS Bitcoin address
    bytes psbtData;
}

interface IHomeChainCoordinator {
// Put functions that are must required for the home chain coordinator
}
