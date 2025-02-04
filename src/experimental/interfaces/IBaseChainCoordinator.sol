// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// TODO: Would require to store user address, AVS address, eBTC amount, chainID (to mint), psbt data (Also, timestamp?)
struct MintData {
    bool isMinted;
    uint32 chainId;
    address user;
    uint256 eBTCAmount;
}
// address avsAddress;
// bytes psbtData;

interface IBaseChainCoordinator {
// Put functions that are must required for the base chain coordinator
}
