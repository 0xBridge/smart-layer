// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract TransactionMetadataUtils {
    // Error codes
    error INVALID_TRANSACTION_FORMAT();
    error NO_METADATA_FOUND();
    error INVALID_METADATA_LENGTH();
    error INVALID_BUFFER_READ();

    struct TransactionOutput {
        uint64 value;
        bytes script;
    }

    struct TransactionMetadata {
        bytes receiverAddress; // hex encoded address
        uint256 lockedAmount; // BigInt value
        uint32 chainId; // 32-bit chain ID
        uint256 baseTokenAmount; // BigInt value
    }

    struct BufferReader {
        bytes data;
        uint256 offset;
    }

    /// @notice Decode transaction metadata from raw transaction hex
    /// @param rawTxHex Raw transaction hex string
    /// @return metadata Decoded transaction metadata
    function decodeTransactionMetadata(bytes memory rawTxHex)
        public
        pure
        returns (TransactionMetadata memory metadata)
    {
        // Parse transaction outputs
        TransactionOutput[] memory outputs = parseTransactionOutputs(rawTxHex);

        // Find OP_RETURN output
        bytes memory opReturnData;
        bool found = false;

        for (uint256 i = 0; i < outputs.length; i++) {
            // Check if script starts with OP_RETURN (0x6a)
            if (outputs[i].script.length > 0 && outputs[i].script[0] == 0x6a) {
                // Extract the OP_RETURN data (skip OP_RETURN opcode)
                opReturnData = extractOpReturnData(outputs[i].script);
                found = true;
                break;
            }
        }

        if (!found) {
            revert NO_METADATA_FOUND();
        }

        // Decode metadata from OP_RETURN data
        return decodeBinaryMetadataBuffer(opReturnData);
    }

    /// @notice Parse transaction outputs from raw transaction
    /// @param rawTx Raw transaction bytes
    /// @return outputs Array of transaction outputs
    function parseTransactionOutputs(bytes memory rawTx) public pure returns (TransactionOutput[] memory outputs) {
        BufferReader memory reader = BufferReader({data: rawTx, offset: 0});

        // Skip version (4 bytes)
        reader.offset += 4;

        // Skip input count and inputs (simplified for this example)
        // In a real implementation, you would need to properly parse inputs
        reader.offset += findOutputsStart(rawTx);

        // Read output count (VarInt)
        uint64 outputCount = readVarInt(reader);
        outputs = new TransactionOutput[](outputCount);

        // Read outputs
        for (uint64 i = 0; i < outputCount; i++) {
            outputs[i] = parseOutput(reader);
        }
    }

    /// @notice Parse a single transaction output
    /// @param reader Buffer reader state
    /// @return output Parsed transaction output
    function parseOutput(BufferReader memory reader) public pure returns (TransactionOutput memory output) {
        // Read value (8 bytes)
        output.value = uint64(readUint64(reader));

        // Read script
        uint64 scriptLength = readVarInt(reader);
        output.script = new bytes(scriptLength);
        for (uint64 i = 0; i < scriptLength; i++) {
            output.script[i] = reader.data[reader.offset + i];
        }
        reader.offset += scriptLength;
    }

    /// @notice Extract OP_RETURN data from script
    /// @param script Script bytes
    /// @return data OP_RETURN data
    function extractOpReturnData(bytes memory script) public pure returns (bytes memory) {
        require(script.length > 2 && script[0] == 0x6a, "Not an OP_RETURN script");

        // Skip OP_RETURN opcode and push opcode
        uint256 dataStart = 2;
        uint256 dataLength = uint8(script[1]);

        bytes memory data = new bytes(dataLength);
        for (uint256 i = 0; i < dataLength; i++) {
            data[i] = script[dataStart + i];
        }

        return data;
    }

    /// @notice Decode binary metadata buffer
    /// @param buffer Binary metadata buffer
    /// @return metadata Decoded transaction metadata
    function decodeBinaryMetadataBuffer(bytes memory buffer)
        public
        pure
        returns (TransactionMetadata memory metadata)
    {
        BufferReader memory reader = BufferReader({data: buffer, offset: 0});

        // Read receiver address
        metadata.receiverAddress = readLengthPrefixed(reader);

        // Read locked amount
        bytes memory lockedAmountBytes = readLengthPrefixed(reader);
        metadata.lockedAmount = bytesToUint256(lockedAmountBytes);

        // Read chain ID (4 bytes)
        metadata.chainId = uint32(readUint32(reader));

        // Read base token amount
        bytes memory baseTokenAmountBytes = readLengthPrefixed(reader);
        metadata.baseTokenAmount = bytesToUint256(baseTokenAmountBytes);
    }

    /// @notice Read length-prefixed data from buffer
    /// @param reader Buffer reader state
    /// @return data Length-prefixed data
    function readLengthPrefixed(BufferReader memory reader) public pure returns (bytes memory) {
        uint16 length = uint16(readUint16(reader));
        bytes memory data = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            data[i] = reader.data[reader.offset + i];
        }
        reader.offset += length;

        return data;
    }

    /// @notice Read VarInt from buffer
    /// @param reader Buffer reader state
    /// @return value Read VarInt value
    function readVarInt(BufferReader memory reader) public pure returns (uint64 value) {
        uint8 first = uint8(reader.data[reader.offset++]);

        if (first < 0xfd) {
            return uint64(first);
        } else if (first == 0xfd) {
            return uint64(readUint16(reader));
        } else if (first == 0xfe) {
            return uint64(readUint32(reader));
        } else {
            return readUint64(reader);
        }
    }

    /// @notice Convert bytes to uint256
    /// @param data Bytes to convert
    /// @return result Converted uint256 value
    function bytesToUint256(bytes memory data) public pure returns (uint256 result) {
        for (uint256 i = 0; i < data.length; i++) {
            result = result * 256 + uint8(data[i]);
        }
    }

    // Helper functions for reading different integer sizes
    function readUint16(BufferReader memory reader) public pure returns (uint16) {
        require(reader.offset + 2 <= reader.data.length, "Buffer overrun");
        uint16 value = uint16(uint8(reader.data[reader.offset])) << 8 | uint16(uint8(reader.data[reader.offset + 1]));
        reader.offset += 2;
        return value;
    }

    function readUint32(BufferReader memory reader) public pure returns (uint32) {
        require(reader.offset + 4 <= reader.data.length, "Buffer overrun");
        uint32 value = uint32(uint8(reader.data[reader.offset])) << 24
            | uint32(uint8(reader.data[reader.offset + 1])) << 16 | uint32(uint8(reader.data[reader.offset + 2])) << 8
            | uint32(uint8(reader.data[reader.offset + 3]));
        reader.offset += 4;
        return value;
    }

    function readUint64(BufferReader memory reader) public pure returns (uint64) {
        require(reader.offset + 8 <= reader.data.length, "Buffer overrun");
        uint64 value = uint64(uint8(reader.data[reader.offset])) << 56
            | uint64(uint8(reader.data[reader.offset + 1])) << 48 | uint64(uint8(reader.data[reader.offset + 2])) << 40
            | uint64(uint8(reader.data[reader.offset + 3])) << 32 | uint64(uint8(reader.data[reader.offset + 4])) << 24
            | uint64(uint8(reader.data[reader.offset + 5])) << 16 | uint64(uint8(reader.data[reader.offset + 6])) << 8
            | uint64(uint8(reader.data[reader.offset + 7]));
        reader.offset += 8;
        return value;
    }

    /// @notice Find the start of outputs in a transaction
    /// @param rawTx Raw transaction bytes
    /// @return offset Offset where outputs start
    function findOutputsStart(bytes memory rawTx) public pure returns (uint256 offset) {
        // Skip version (4 bytes)
        offset = 4;

        // Handle witness flag
        bool hasWitness = (rawTx[offset] == 0x00 && rawTx[offset + 1] == 0x01);
        if (hasWitness) {
            offset += 2;
        }

        // Read input count and skip inputs
        BufferReader memory reader = BufferReader({data: rawTx, offset: offset});

        uint64 inputCount = readVarInt(reader);
        for (uint64 i = 0; i < inputCount; i++) {
            // Skip outpoint (36 bytes)
            reader.offset += 36;

            // Skip script
            uint64 scriptLength = readVarInt(reader);
            reader.offset += scriptLength;

            // Skip sequence (4 bytes)
            reader.offset += 4;
        }

        return reader.offset;
    }
}
