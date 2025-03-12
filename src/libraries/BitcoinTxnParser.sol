// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
    error UNKNOWN_SCRIPT_TYPE();

    // Bitcoin script constants
    uint8 constant OP_RETURN = 0x6a;

    // Address type constants (for internal use)
    uint8 constant TYPE_P2PKH = 1; // Pay to Public Key Hash (legacy)
    uint8 constant TYPE_P2SH = 2; // Pay to Script Hash
    uint8 constant TYPE_P2WPKH = 3; // Pay to Witness Public Key Hash (segwit v0)
    uint8 constant TYPE_P2WSH = 4; // Pay to Witness Script Hash (segwit v0)
    uint8 constant TYPE_P2TR = 5; // Pay to Taproot (segwit v1)

    struct Input {
        bytes32 txid;
        uint32 vout;
        bytes script;
        uint32 sequence;
    }

    struct Output {
        uint64 value;
        bytes script;
    }

    struct Transaction {
        uint32 version;
        Input[] inputs;
        Output[] outputs;
        uint32 locktime;
    }

    struct TransactionMetadata {
        address receiverAddress;
        uint256 lockedAmount;
        uint32 chainId;
        uint256 nativeTokenAmount;
    }

    // Simple struct for output information
    struct UnlockTxnData {
        string btcAddress;
        uint64 amount;
    }

    /// @notice Decodes metadata from OP_RETURN data into a structured format
    /// @param data The raw metadata bytes from OP_RETURN output
    /// @return Structured metadata containing receiver address, locked Amount, chain ID, and base token amount
    /// @dev Uses assembly for efficient byte manipulation and data extraction
    function decodeMetadata(bytes memory data) internal pure returns (TransactionMetadata memory) {
        if (data.length != 48) {
            // Subject to change based on metadata format
            revert INVALID_OP_RETURN_DATA_LENGTH();
        }
        address receiverAddress;
        uint256 lockedAmount;
        uint32 chainId;
        uint256 nativeTokenAmount;

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
            nativeTokenAmount := shr(192, mload(ptr))
        }

        return TransactionMetadata({
            receiverAddress: receiverAddress,
            lockedAmount: lockedAmount,
            chainId: chainId,
            nativeTokenAmount: nativeTokenAmount
        });
    }

    /// @notice Extracts OP_RETURN data from a raw Bitcoin transaction
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @return bytes The extracted OP_RETURN data
    /// @dev Searches through transaction outputs for OP_RETURN (0x6a) and handles different push operations
    function decodeBitcoinTxn(bytes memory rawTxn) internal pure returns (bytes memory) {
        Transaction memory txn = parseTransaction(rawTxn);

        // Find OP_RETURN output
        bytes memory opReturnData;
        for (uint256 i = 0; i < txn.outputs.length; i++) {
            if (txn.outputs[i].script.length > 0 && uint8(txn.outputs[i].script[0]) == OP_RETURN) {
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
    function extractBytes(bytes memory data, uint256 start, uint256 length)
        internal
        pure
        returns (bytes memory result)
    {
        if (start + length > data.length) revert INVALID_TRANSACTION_FORMAT();

        result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    /// @notice Parses a raw Bitcoin transaction into a structured format
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @return txn Structured transaction data containing version, inputs, outputs, and locktime
    function parseTransaction(bytes memory rawTxn) internal pure returns (Transaction memory txn) {
        uint256 offset = 0;

        // Parse version (4 bytes)
        bytes memory versionBytes = extractBytes(rawTxn, offset, 4);
        txn.version = uint32(bytes4(versionBytes));
        offset += 4;

        // Check for segwit flag
        bool isSegwit = false;
        if (rawTxn.length > offset + 1 && rawTxn[offset] == 0x00 && rawTxn[offset + 1] == 0x01) {
            isSegwit = true;
            offset += 2;
        }

        // Parse input count (VarInt)
        (uint256 inputCount, uint256 inputCountSize) = parseVarInt(rawTxn, offset);
        offset += inputCountSize;

        // Parse inputs
        txn.inputs = new Input[](inputCount);
        for (uint256 i = 0; i < inputCount; i++) {
            // Previous txid (32 bytes) - reverse byte order
            bytes memory txidBytes = extractBytes(rawTxn, offset, 32);
            bytes memory reversedTxid = new bytes(32);
            for (uint256 j = 0; j < 32; j++) {
                reversedTxid[j] = txidBytes[31 - j];
            }
            txn.inputs[i].txid = bytes32(reversedTxid);
            offset += 32;

            // Previous vout (4 bytes)
            bytes memory voutBytes = extractBytes(rawTxn, offset, 4);
            txn.inputs[i].vout = uint32(bytes4(voutBytes));
            offset += 4;

            // Script length (VarInt)
            (uint256 scriptLength, uint256 scriptLengthSize) = parseVarInt(rawTxn, offset);
            offset += scriptLengthSize;

            // Script
            txn.inputs[i].script = extractBytes(rawTxn, offset, scriptLength);
            offset += scriptLength;

            // Sequence (4 bytes)
            bytes memory sequenceBytes = extractBytes(rawTxn, offset, 4);
            txn.inputs[i].sequence = uint32(bytes4(sequenceBytes));
            offset += 4;
        }

        // Parse output count (VarInt)
        (uint256 outputCount, uint256 outputCountSize) = parseVarInt(rawTxn, offset);
        offset += outputCountSize;

        // Parse outputs
        txn.outputs = new Output[](outputCount);
        for (uint256 i = 0; i < outputCount; i++) {
            // Value (8 bytes) - little-endian
            bytes memory valueBytes = extractBytes(rawTxn, offset, 8);

            // Convert little-endian bytes to uint64
            uint64 value = 0;
            for (uint256 j = 0; j < 8; j++) {
                value |= uint64(uint8(valueBytes[j])) << (j * 8);
            }

            txn.outputs[i].value = value;
            offset += 8;

            // Script length (VarInt)
            (uint256 scriptLength, uint256 scriptLengthSize) = parseVarInt(rawTxn, offset);
            offset += scriptLengthSize;

            // Script
            txn.outputs[i].script = extractBytes(rawTxn, offset, scriptLength);
            offset += scriptLength;
        }

        // Skip witness data if segwit
        if (isSegwit) {
            for (uint256 i = 0; i < inputCount; i++) {
                (uint256 witnessCount, uint256 witnessCountSize) = parseVarInt(rawTxn, offset);
                offset += witnessCountSize;

                for (uint256 j = 0; j < witnessCount; j++) {
                    (uint256 witnessLength, uint256 witnessLengthSize) = parseVarInt(rawTxn, offset);
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
    /// @param offset The offset value to start parsing from
    /// @return value The parsed integer value
    /// @return consumed The number of bytes consumed by the VarInt
    /// @dev Handles all VarInt formats: uint8, uint16, uint32, and uint64
    function parseVarInt(bytes memory data, uint256 offset) internal pure returns (uint256 value, uint256 consumed) {
        if (data.length < offset + 1) revert INVALID_VAR_INT_FORMAT();
        uint8 first = uint8(data[offset]);

        if (first < 0xfd) {
            return (first, 1);
        } else if (first == 0xfd) {
            if (data.length < offset + 3) revert INVALID_VAR_INT_FORMAT();
            bytes memory lengthBytes = extractBytes(data, offset + 1, 2);
            // Parse little-endian bytes
            return (uint16(uint8(lengthBytes[0])) | (uint16(uint8(lengthBytes[1])) << 8), 3);
        } else if (first == 0xfe) {
            if (data.length < offset + 5) revert INVALID_VAR_INT_FORMAT();
            bytes memory lengthBytes = extractBytes(data, offset + 1, 4);
            // Parse little-endian bytes
            uint32 val = uint32(uint8(lengthBytes[0])) | (uint32(uint8(lengthBytes[1])) << 8)
                | (uint32(uint8(lengthBytes[2])) << 16) | (uint32(uint8(lengthBytes[3])) << 24);
            return (val, 5);
        } else {
            if (data.length < offset + 9) revert INVALID_VAR_INT_FORMAT();
            bytes memory lengthBytes = extractBytes(data, offset + 1, 8);
            // Parse little-endian bytes
            uint64 val = uint64(uint8(lengthBytes[0])) | (uint64(uint8(lengthBytes[1])) << 8)
                | (uint64(uint8(lengthBytes[2])) << 16) | (uint64(uint8(lengthBytes[3])) << 24)
                | (uint64(uint8(lengthBytes[4])) << 32) | (uint64(uint8(lengthBytes[5])) << 40)
                | (uint64(uint8(lengthBytes[6])) << 48) | (uint64(uint8(lengthBytes[7])) << 56);
            return (val, 9);
        }
    }

    /// @notice Determines the Bitcoin address type from a script
    /// @param script The output script
    /// @return The detected address type (1=P2PKH, 2=P2SH, 3=P2WPKH, 4=P2WSH, 5=P2TR, 0=unknown)
    function getScriptType(bytes memory script) internal pure returns (uint8) {
        if (script.length == 0) return 0;

        // P2PKH: OP_DUP OP_HASH160 <pubKeyHash> OP_EQUALVERIFY OP_CHECKSIG
        if (
            script.length == 25 && script[0] == 0x76 && script[1] == 0xa9 && script[2] == 0x14 && script[23] == 0x88
                && script[24] == 0xac
        ) {
            return TYPE_P2PKH;
        }

        // P2SH: OP_HASH160 <scriptHash> OP_EQUAL
        if (script.length == 23 && script[0] == 0xa9 && script[1] == 0x14 && script[22] == 0x87) {
            return TYPE_P2SH;
        }

        // P2WPKH: OP_0 <pubKeyHash>
        if (script.length == 22 && script[0] == 0x00 && script[1] == 0x14) {
            return TYPE_P2WPKH;
        }

        // P2WSH: OP_0 <scriptHash>
        if (script.length == 34 && script[0] == 0x00 && script[1] == 0x20) {
            return TYPE_P2WSH;
        }

        // P2TR: OP_1 <x-only pubkey>
        if (script.length == 34 && script[0] == 0x51 && script[1] == 0x20) {
            return TYPE_P2TR;
        }

        return 0; // Unknown script type
    }

    /// @notice Extracts the hash from a script based on its type
    /// @param script The output script
    /// @return The extracted hash/key data
    function extractScriptData(bytes memory script) internal pure returns (bytes memory) {
        uint8 scriptType = getScriptType(script);

        if (scriptType == TYPE_P2PKH) {
            return extractBytes(script, 3, 20); // pubKeyHash
        } else if (scriptType == TYPE_P2SH) {
            return extractBytes(script, 2, 20); // scriptHash
        } else if (scriptType == TYPE_P2WPKH) {
            return extractBytes(script, 2, 20); // pubKeyHash
        } else if (scriptType == TYPE_P2WSH) {
            return extractBytes(script, 2, 32); // scriptHash
        } else if (scriptType == TYPE_P2TR) {
            return extractBytes(script, 2, 32); // x-only pubkey
        } else {
            return script; // Return full script for unknown types
        }
    }

    /// @notice Creates a simplified Bitcoin address string representation
    /// @param scriptType The type of script
    /// @param scriptData The extracted script data (hash or key)
    /// @param isTestnet Whether to use testnet prefixes
    /// @return A string representation of the Bitcoin address
    function createAddressString(uint8 scriptType, bytes memory scriptData, bool isTestnet)
        internal
        pure
        returns (string memory)
    {
        string memory prefix;

        if (scriptType == TYPE_P2PKH) {
            prefix = isTestnet ? "mtest_" : "1_";
        } else if (scriptType == TYPE_P2SH) {
            prefix = isTestnet ? "2test_" : "3_";
        } else if (scriptType == TYPE_P2WPKH) {
            prefix = isTestnet ? "tb1q_" : "bc1q_";
        } else if (scriptType == TYPE_P2WSH) {
            prefix = isTestnet ? "tb1q_" : "bc1q_";
        } else if (scriptType == TYPE_P2TR) {
            prefix = isTestnet ? "tb1p_" : "bc1p_";
        } else {
            return "unknown_script_type";
        }

        return string(abi.encodePacked(prefix, toHexString(scriptData)));
    }

    /// @notice Helper to convert bytes to hex string
    /// @param data The bytes to convert
    /// @return The hex string representation
    function toHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(data.length * 2);

        for (uint256 i = 0; i < data.length; i++) {
            result[i * 2] = hexChars[uint8(data[i]) >> 4];
            result[i * 2 + 1] = hexChars[uint8(data[i]) & 0x0f];
        }

        return string(result);
    }

    /// @notice Extracts the output addresses and amounts from a Bitcoin transaction
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @param isTestnet Whether to use testnet address formats
    /// @return outputs Array of output info (addresses and amounts)
    function extractUnlockOutputs(bytes calldata rawTxn, bool isTestnet)
        internal
        pure
        returns (UnlockTxnData[] memory outputs)
    {
        Transaction memory txn = parseTransaction(rawTxn);

        // Extract outputs
        outputs = new UnlockTxnData[](txn.outputs.length);
        for (uint256 i = 0; i < txn.outputs.length; i++) {
            uint8 scriptType = getScriptType(txn.outputs[i].script);
            bytes memory scriptData = extractScriptData(txn.outputs[i].script);

            outputs[i].btcAddress = createAddressString(scriptType, scriptData, isTestnet);
            outputs[i].amount = txn.outputs[i].value;
        }
    }
}
