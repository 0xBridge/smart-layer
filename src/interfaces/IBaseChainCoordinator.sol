// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {
    ILayerZeroReceiver, Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";

struct MintData {
    bool status;
    address user;
    uint256 lockedAmount;
}

interface IBaseChainCoordinator is ILayerZeroReceiver {}
