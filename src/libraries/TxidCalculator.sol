// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BitcoinUtils} from "./BitcoinUtils.sol";
import {BitcoinTxnParser} from "./BitcoinTxnParser.sol";

library TxidCalculator {
    using BitcoinUtils for *;
    using BitcoinTxnParser for *;

    /// @notice Calculates txid from raw transaction hex
    /// @param rawTxn The raw transaction bytes
    /// @return The transaction ID (in Bitcoin's display format - reversed)
    function calculateTxid(bytes memory rawTxn) internal view returns (bytes32) {
        // For segwit transactions, we need to:
        // 1. Keep the version (4 bytes)
        // 2. Remove marker (0x00) and flag (0x01)
        // 3. Keep input count and inputs (without witness)
        // 4. Keep output count and outputs
        // 5. Keep locktime
        // 6. Double SHA256 and reverse

        uint256 cursor = 0;
        bytes memory stripped;

        // Copy version (4 bytes)
        bytes memory version = BitcoinTxnParser.extractBytes(rawTxn, 0, 4);
        cursor = 4;

        // Check for segwit
        bool isSegwit = (rawTxn[cursor] == 0x00 && rawTxn[cursor + 1] == 0x01);

        if (isSegwit) {
            // Skip marker and flag
            cursor += 2;

            // Get input count
            (uint256 inputCount, uint256 countSize) = BitcoinTxnParser.parseVarInt(rawTxn, cursor);
            bytes memory inputCountBytes = BitcoinTxnParser.extractBytes(rawTxn, cursor, countSize);
            cursor += countSize;

            // Copy inputs (without witness data)
            bytes memory inputs;
            uint256 inputsStart = cursor;
            for (uint256 i = 0; i < inputCount; i++) {
                // 32 bytes txid + 4 bytes vout
                cursor += 36;
                // Script
                (uint256 scriptLen, uint256 scriptLenSize) = BitcoinTxnParser.parseVarInt(rawTxn, cursor);
                cursor += scriptLenSize + scriptLen;
                // Sequence
                cursor += 4;
            }
            inputs = BitcoinTxnParser.extractBytes(rawTxn, inputsStart, cursor - inputsStart);

            // Get outputs
            (uint256 outputCount, uint256 outputCountSize) = BitcoinTxnParser.parseVarInt(rawTxn, cursor);
            bytes memory outputCountBytes = BitcoinTxnParser.extractBytes(rawTxn, cursor, outputCountSize);
            cursor += outputCountSize;

            uint256 outputsStart = cursor;
            for (uint256 i = 0; i < outputCount; i++) {
                // 8 bytes value
                cursor += 8;
                // Script
                (uint256 scriptLen, uint256 scriptLenSize) = BitcoinTxnParser.parseVarInt(rawTxn, cursor);
                cursor += scriptLenSize + scriptLen;
            }
            bytes memory outputs = BitcoinTxnParser.extractBytes(rawTxn, outputsStart, cursor - outputsStart);

            // Get locktime (last 4 bytes)
            bytes memory locktime = BitcoinTxnParser.extractBytes(rawTxn, rawTxn.length - 4, 4);

            // Combine all parts
            stripped = bytes.concat(version, inputCountBytes, inputs, outputCountBytes, outputs, locktime);
        } else {
            // Non-segwit transaction can be used as is
            stripped = rawTxn;
        }

        // Double SHA256 hash
        bytes32 hash = BitcoinUtils.sha256DoubleHash(stripped);

        // Reverse for Bitcoin's display format
        return BitcoinUtils.reverseBytes32(hash);
    }
}
