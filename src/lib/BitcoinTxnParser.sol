// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title BitcoinTxnParser
/// @notice Library for parsing Bitcoin transactions and extracting OP_RETURN metadata
/// @dev Handles both legacy and segwit transaction formats
library BitcoinTxnParser {
    // Custom errors
    error INVALID_OP_RETURN_OUTPUT();
    error UNSUPPORTED_PUSH_OPERATION();
    error INVALID_PUSH_DATA_1();
    error INVALID_PUSH_DATA_2();
    error INVALID_OP_RETURN_DATA_LENGTH();
    error NO_OP_RETURN_FOUND();
    error INVALID_TRANSACTION_FORMAT();
    error INVALID_VAR_INT_FORMAT();

    struct Output {
        uint64 value;
        bytes script;
    }

    struct Transaction {
        uint32 version;
        Output[] outputs;
        uint32 locktime;
    }

    struct TransactionMetadata {
        address receiverAddress;
        uint256 lockedAmount;
        uint32 chainId;
        uint256 baseTokenAmount;
    }

    /// @notice Decodes metadata from OP_RETURN data into a structured format
    /// @param data The raw metadata bytes from OP_RETURN output
    /// @return metadata Structured metadata containing receiver address, amounts, and chain ID
    /// @dev Uses assembly for efficient byte manipulation and data extraction
    function decodeMetadata(bytes memory data) internal pure returns (TransactionMetadata memory) {
        address receiverAddress;
        uint256 lockedAmount;
        uint32 chainId;
        uint256 baseTokenAmount;

        assembly {
            let ptr := add(data, 32)

            // Read receiver address
            let addrLength := shr(240, mload(ptr))
            ptr := add(ptr, 2)
            receiverAddress := shr(96, mload(ptr))
            ptr := add(ptr, addrLength)

            // Read locked amount
            let lockedAmountLength := shr(240, mload(ptr))
            ptr := add(ptr, 2)
            lockedAmount := shr(192, mload(ptr))
            ptr := add(ptr, lockedAmountLength)

            // Read chain ID
            let chainIdLength := shr(240, mload(ptr))
            ptr := add(ptr, 2)
            chainId := shr(224, mload(ptr))
            ptr := add(ptr, chainIdLength)

            // Read base token amount
            ptr := add(ptr, 2) // Skip length bytes
            baseTokenAmount := shr(192, mload(ptr))
        }

        return TransactionMetadata({
            receiverAddress: receiverAddress,
            lockedAmount: lockedAmount,
            chainId: chainId,
            baseTokenAmount: baseTokenAmount
        });
    }

    /// @notice Extracts OP_RETURN data from a raw Bitcoin transaction
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @return bytes The extracted OP_RETURN data
    /// @dev Searches through transaction outputs for OP_RETURN (0x6a) and handles different push operations
    function decodeBitcoinTxn(bytes calldata rawTxn) internal pure returns (bytes memory) {
        Transaction memory txn = parseTransaction(rawTxn);

        // Find OP_RETURN output
        bytes memory opReturnData;
        for (uint256 i = 0; i < txn.outputs.length; i++) {
            if (txn.outputs[i].script.length > 0 && txn.outputs[i].script[0] == 0x6a) {
                bytes memory script = txn.outputs[i].script;
                if (script.length < 3) revert INVALID_OP_RETURN_OUTPUT();

                uint8 pushOpcode = uint8(script[1]);
                uint256 dataLength;
                uint256 dataStart;

                if (pushOpcode >= 0x01 && pushOpcode <= 0x4b) {
                    dataLength = pushOpcode;
                    dataStart = 2;
                } else if (pushOpcode == 0x4c) {
                    if (script.length < 4) revert INVALID_PUSH_DATA_1();
                    dataLength = uint8(script[2]);
                    dataStart = 3;
                } else if (pushOpcode == 0x4d) {
                    if (script.length < 5) revert INVALID_PUSH_DATA_2();
                    bytes memory lengthBytes = new bytes(2);
                    lengthBytes[0] = script[2];
                    lengthBytes[1] = script[3];
                    dataLength = uint16(bytes2(lengthBytes));
                    dataStart = 4;
                } else {
                    revert UNSUPPORTED_PUSH_OPERATION();
                }

                if (script.length < dataStart + dataLength) revert INVALID_OP_RETURN_DATA_LENGTH();
                opReturnData = new bytes(dataLength);
                for (uint256 j = 0; j < dataLength; j++) {
                    opReturnData[j] = script[dataStart + j];
                }
                break;
            }
        }

        if (opReturnData.length == 0) revert NO_OP_RETURN_FOUND();
        return opReturnData;
    }

    /// @notice Helper function to extract bytes from calldata
    /// @param data Source calldata bytes
    /// @param start Starting position in the source data
    /// @param length Number of bytes to extract
    /// @return result The extracted bytes
    function extractBytes(bytes calldata data, uint256 start, uint256 length)
        internal
        pure
        returns (bytes memory result)
    {
        result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    /// @notice Parses a raw Bitcoin transaction into a structured format
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @return txn Structured transaction data containing version, outputs, and locktime
    /// @dev Handles both legacy and segwit transaction formats
    function parseTransaction(bytes calldata rawTxn) internal pure returns (Transaction memory txn) {
        uint256 offset = 0;

        // Parse version (4 bytes)
        bytes memory versionBytes = extractBytes(rawTxn, offset, 4);
        txn.version = uint32(bytes4(versionBytes));
        offset += 4;

        // Check for segwit flag
        bool isSegwit = false;
        if (rawTxn[offset] == 0x00 && rawTxn[offset + 1] == 0x01) {
            isSegwit = true;
            offset += 2;
        }

        // Parse input count (VarInt)
        (uint256 inputCount, uint256 inputCountSize) = parseVarInt(rawTxn[offset:]);
        offset += inputCountSize;

        // Skip inputs
        for (uint256 i = 0; i < inputCount; i++) {
            offset += 36; // Previous output (32 + 4)

            // Script length (VarInt)
            (uint256 scriptLength, uint256 scriptLengthSize) = parseVarInt(rawTxn[offset:]);
            offset += scriptLengthSize + scriptLength;

            offset += 4; // Sequence
        }

        // Parse output count (VarInt)
        (uint256 outputCount, uint256 outputCountSize) = parseVarInt(rawTxn[offset:]);
        offset += outputCountSize;

        // Parse outputs
        txn.outputs = new Output[](outputCount);
        for (uint256 i = 0; i < outputCount; i++) {
            // Value (8 bytes)
            bytes memory valueBytes = extractBytes(rawTxn, offset, 8);
            txn.outputs[i].value = uint64(bytes8(valueBytes));
            offset += 8;

            // Script length (VarInt)
            (uint256 scriptLength, uint256 scriptLengthSize) = parseVarInt(rawTxn[offset:]);
            offset += scriptLengthSize;

            // Script
            txn.outputs[i].script = extractBytes(rawTxn, offset, scriptLength);
            offset += scriptLength;
        }

        // Skip witness data
        if (isSegwit) {
            for (uint256 i = 0; i < inputCount; i++) {
                (uint256 witnessCount, uint256 witnessCountSize) = parseVarInt(rawTxn[offset:]);
                offset += witnessCountSize;

                for (uint256 j = 0; j < witnessCount; j++) {
                    (uint256 witnessLength, uint256 witnessLengthSize) = parseVarInt(rawTxn[offset:]);
                    offset += witnessLengthSize + witnessLength;
                }
            }
        }

        // Parse locktime (4 bytes)
        if (offset + 4 > rawTxn.length) revert INVALID_TRANSACTION_FORMAT();
        bytes memory locktimeBytes = extractBytes(rawTxn, offset, 4);
        txn.locktime = uint32(bytes4(locktimeBytes));

        return txn;
    }

    /// @notice Parses Bitcoin's variable integer format
    /// @param data The raw bytes containing a VarInt
    /// @return value The parsed integer value
    /// @return offset The number of bytes consumed by the VarInt
    /// @dev Handles all VarInt formats: uint8, uint16, uint32, and uint64
    function parseVarInt(bytes calldata data) internal pure returns (uint256 value, uint256 offset) {
        if (data.length < 1) revert INVALID_VAR_INT_FORMAT();
        uint8 first = uint8(data[0]);

        if (first < 0xfd) {
            return (first, 1);
        } else if (first == 0xfd) {
            if (data.length < 3) revert INVALID_VAR_INT_FORMAT();
            bytes memory lengthBytes = extractBytes(data, 1, 2);
            return (uint16(bytes2(lengthBytes)), 3);
        } else if (first == 0xfe) {
            if (data.length < 5) revert INVALID_VAR_INT_FORMAT();
            bytes memory lengthBytes = extractBytes(data, 1, 4);
            return (uint32(bytes4(lengthBytes)), 5);
        } else {
            if (data.length < 9) revert INVALID_VAR_INT_FORMAT();
            bytes memory lengthBytes = extractBytes(data, 1, 8);
            return (uint64(bytes8(lengthBytes)), 9);
        }
    }
}
