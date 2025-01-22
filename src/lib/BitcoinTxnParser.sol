// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library BitcoinTxnParser {
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
    /// @return TransactionMetadata Structured metadata containing receiver address, amounts, and chain ID
    function decodeMetadata(bytes calldata data) internal pure returns (TransactionMetadata memory) {
        uint256 offset = 0;

        // Read receiver address
        uint16 addrLength = uint16(bytes2(data[offset:offset + 2]));
        offset += 2;
        bytes20 receiverBytes = bytes20(data[offset:offset + addrLength]);
        offset += addrLength;

        // Read locked amount (8 bytes)
        uint16 lockedAmountLength = uint16(bytes2(data[offset:offset + 2]));
        offset += 2;
        bytes memory lockedAmountBytes = new bytes(8);
        for (uint256 i = 0; i < 8; i++) {
            lockedAmountBytes[i] = data[offset + i];
        }
        uint256 lockedAmount = uint64(bytes8(lockedAmountBytes)); // Use uint64 for proper conversion
        offset += lockedAmountLength;

        // Read chain ID (4 bytes)
        uint16 chainIdLength = uint16(bytes2(data[offset:offset + 2]));
        offset += 2;
        bytes memory chainIdBytes = new bytes(4);
        for (uint256 i = 0; i < 4; i++) {
            chainIdBytes[i] = data[offset + i];
        }
        uint32 chainId = uint32(bytes4(chainIdBytes));
        offset += chainIdLength;

        // Read base token amount (8 bytes)
        // uint16 baseTokenLength = uint16(bytes2(data[offset:offset + 2]));
        offset += 2;
        bytes memory baseTokenBytes = new bytes(8);
        for (uint256 i = 0; i < 8; i++) {
            baseTokenBytes[i] = data[offset + i];
        }
        uint256 baseTokenAmount = uint64(bytes8(baseTokenBytes)); // Use uint64 for proper conversion

        return TransactionMetadata({
            receiverAddress: address(uint160(uint256(uint160(receiverBytes)))),
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
                // Found OP_RETURN output
                bytes memory script = txn.outputs[i].script;
                require(script.length >= 3, "Invalid OP_RETURN output");

                uint8 pushOpcode = uint8(script[1]);
                uint256 dataLength;
                uint256 dataStart;

                if (pushOpcode >= 0x01 && pushOpcode <= 0x4b) {
                    // Direct push of N bytes where N is the opcode value
                    dataLength = pushOpcode;
                    dataStart = 2;
                } else if (pushOpcode == 0x4c) {
                    // OP_PUSHDATA1: next byte contains N
                    require(script.length >= 4, "Invalid OP_PUSHDATA1");
                    dataLength = uint8(script[2]);
                    dataStart = 3;
                } else if (pushOpcode == 0x4d) {
                    // OP_PUSHDATA2: next 2 bytes contain N
                    require(script.length >= 5, "Invalid OP_PUSHDATA2");
                    bytes memory lengthBytes = new bytes(2);
                    lengthBytes[0] = script[2];
                    lengthBytes[1] = script[3];
                    dataLength = uint16(bytes2(lengthBytes));
                    dataStart = 4;
                } else {
                    revert("Unsupported push operation in OP_RETURN");
                }

                require(script.length >= dataStart + dataLength, "Invalid OP_RETURN data length");
                opReturnData = new bytes(dataLength);
                for (uint256 j = 0; j < dataLength; j++) {
                    opReturnData[j] = script[dataStart + j];
                }
                break;
            }
        }

        require(opReturnData.length > 0, "No OP_RETURN output found");
        return opReturnData;
    }

    /// @notice Helper function to extract bytes from calldata
    /// @param data Source calldata bytes
    /// @param start Starting position in the source data
    /// @param length Number of bytes to extract
    /// @return bytes The extracted bytes
    function extractBytes(bytes calldata data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    /// @notice Parses a raw Bitcoin transaction into a structured format
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @return Transaction Structured transaction data containing version, outputs, and locktime
    /// @dev Handles both legacy and segwit transaction formats
    function parseTransaction(bytes calldata rawTxn) internal pure returns (Transaction memory) {
        uint256 offset = 0;
        Transaction memory txn;

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
        require(offset + 4 <= rawTxn.length, "Invalid transaction format");
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
        require(data.length >= 1, "Invalid VarInt");
        uint8 first = uint8(data[0]);

        if (first < 0xfd) {
            return (first, 1);
        } else if (first == 0xfd) {
            require(data.length >= 3, "Invalid VarInt");
            bytes memory lengthBytes = extractBytes(data, 1, 2);
            return (uint16(bytes2(lengthBytes)), 3);
        } else if (first == 0xfe) {
            require(data.length >= 5, "Invalid VarInt");
            bytes memory lengthBytes = extractBytes(data, 1, 4);
            return (uint32(bytes4(lengthBytes)), 5);
        } else {
            require(data.length >= 9, "Invalid VarInt");
            bytes memory lengthBytes = extractBytes(data, 1, 8);
            return (uint64(bytes8(lengthBytes)), 9);
        }
    }

    function memoryToCalldata(bytes memory data) internal pure returns (bytes calldata ret) {
        assembly {
            // Get the length of the memory bytes
            let len := mload(data)

            // Get the pointer to the content of the memory bytes
            let content := add(data, 0x20)

            // Set the return value (ret) to be of type bytes calldata
            // pointing to the same memory location
            ret.offset := content
            ret.length := len
        }
    }
}
