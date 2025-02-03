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
    function sendMessage(uint32 _dstEid, string memory _message, bytes calldata _options) external payable;
    // Create function to receive message if required
}
