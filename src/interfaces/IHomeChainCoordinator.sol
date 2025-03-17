// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// TODO: Break PSBTData into separate PSBTData and AVSData (txnType, taprootAddress, networkKey, operators) structs
struct PSBTData {
    bool txnType; // true for mint, false for burn
    bool status; // isMinted or isBurned depending on the transaction type
    uint32 chainId; // Chain Id of the destination chain (currently making use of chainEid)
    address user; // User address (could be the receiver of the eBTC token or the burner of the eBTC token)
    bytes rawTxn; // Raw hex PSBT data for the mint or burn transaction
    string taprootAddress; // Taproot address for the mint or burn transaction
    string networkKey; // AVS Bitcoin address
    address[] operators; // Array of operators with whom AVS network key is created
    uint256 lockedAmount; // Amount locked or unlocked in the mint or burn transaction (NOTE: Can be converted to uint64 as that's the max with 21m BTCs)
    uint256 nativeTokenAmount; // Amount of native token minted on the destination chain (NOTE: Can be made generic to check for the fees at the time of burn)
}

interface IHomeChainCoordinator {
// Put functions that are must required for the home chain coordinator
}
