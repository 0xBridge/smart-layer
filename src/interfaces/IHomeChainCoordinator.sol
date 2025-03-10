// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

struct PSBTData {
    // bool txnType; // true for mint, false for burn
    bool status; // isMinted or isBurned depending on the transaction type
    uint32 chainId;
    address user;
    bytes psbtData;
    uint256 lockedAmount;
    uint256 nativeTokenAmount;
    bytes32 networkPublicKey; // AVS Bitcoin address (TODO: needs to be converted to string)
        // string taprootAddress;
}

interface IHomeChainCoordinator {
// Put functions that are must required for the home chain coordinator
}
