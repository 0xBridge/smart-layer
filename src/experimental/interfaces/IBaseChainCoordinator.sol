// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// TODO: Is timestamp required to track when eBTC was minted? (In case the messgae from the receiver relayer is delayed?)
struct MintData {
    bool isMinted;
    uint32 chainId;
    address user;
    uint256 lockedAmount;
}

interface IBaseChainCoordinator {
// Put functions that are must required for the base chain coordinator
}
