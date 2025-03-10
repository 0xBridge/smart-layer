// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title EnhancedBitcoinTxnParser
/// @notice Library for parsing Bitcoin transactions and extracting detailed output information
/// @dev Handles legacy, segwit, taproot and OP_RETURN outputs with full metadata extraction
library EnhancedBitcoinTxnParser {
    // Custom errors
    error INVALID_OP_RETURN_OUTPUT();
    error UNSUPPORTED_PUSH_OPERATION();
    error INVALID_PUSH_DATA_1();
    error INVALID_PUSH_DATA_2();
    error INVALID_OP_RETURN_DATA_LENGTH();
    error NO_OP_RETURN_FOUND();
    error INVALID_TRANSACTION_FORMAT();
    error INVALID_VAR_INT_FORMAT();
    error INVALID_SCRIPT_FORMAT();
    error UNSUPPORTED_SCRIPT_TYPE();

    // Script type constants
    bytes32 constant TYPE_P2PKH = "p2pkh"; // Pay to Public Key Hash
    bytes32 constant TYPE_P2SH = "p2sh"; // Pay to Script Hash
    bytes32 constant TYPE_V0_P2WPKH = "v0_p2wpkh"; // Pay to Witness Public Key Hash (v0)
    bytes32 constant TYPE_V0_P2WSH = "v0_p2wsh"; // Pay to Witness Script Hash (v0)
    bytes32 constant TYPE_V1_P2TR = "v1_p2tr"; // Pay to Taproot (v1)
    bytes32 constant TYPE_OP_RETURN = "op_return"; // OP_RETURN

    struct Output {
        uint64 value;
        bytes script;
    }

    // Enhanced output structure with detailed information
    struct OutputInfo {
        uint64 value; // Output value in satoshis
        bytes32 scriptType; // Type of script (e.g., p2pkh, v0_p2wpkh, v1_p2tr)
        bytes scriptPubKey; // Raw scriptPubKey
        string scriptPubKeyAsm; // Assembly representation of the script
        string destinationAddress; // Decoded address (if applicable)
        bytes data; // Data (for OP_RETURN outputs)
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
        uint256 nativeTokenAmount;
    }

    /// @notice Parses a raw Bitcoin transaction and extracts detailed information for all outputs
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @return outputs Array of detailed output information
    function parseTransactionOutputs(bytes memory rawTxn) public pure returns (OutputInfo[] memory outputs) {
        Transaction memory txn = parseTransaction(rawTxn);
        outputs = new OutputInfo[](txn.outputs.length);

        for (uint256 i = 0; i < txn.outputs.length; i++) {
            outputs[i] = decodeOutput(txn.outputs[i]);
        }

        return outputs;
    }

    /// @notice Decodes a Bitcoin transaction output into a detailed format
    /// @param output The raw transaction output
    /// @return info Detailed output information including type, address, and value
    function decodeOutput(Output memory output) public pure returns (OutputInfo memory info) {
        info.value = output.value;
        info.scriptPubKey = output.script;

        if (output.script.length == 0) {
            revert INVALID_SCRIPT_FORMAT();
        }

        // Detect script type and extract relevant information
        uint8 firstByte = uint8(output.script[0]);

        // OP_RETURN
        if (firstByte == 0x6a) {
            info.scriptType = TYPE_OP_RETURN;
            info.scriptPubKeyAsm = formatOpReturnAsm(output.script);
            info.data = extractOpReturnData(output.script);
            info.destinationAddress = "";

            // P2PKH: OP_DUP OP_HASH160 <pubKeyHash> OP_EQUALVERIFY OP_CHECKSIG
        } else if (output.script.length == 25 && firstByte == 0x76 && uint8(output.script[1]) == 0xa9) {
            info.scriptType = TYPE_P2PKH;
            // Extract the pub key hash (bytes 3-22)
            bytes memory pubKeyHash = new bytes(20);
            for (uint256 i = 0; i < 20; i++) {
                pubKeyHash[i] = output.script[i + 3];
            }
            info.scriptPubKeyAsm = formatP2PKHAsm(pubKeyHash);
            info.destinationAddress = formatP2PKHAddress(pubKeyHash);

            // P2SH: OP_HASH160 <scriptHash> OP_EQUAL
        } else if (output.script.length == 23 && firstByte == 0xa9) {
            info.scriptType = TYPE_P2SH;
            // Extract the script hash (bytes 2-21)
            bytes memory scriptHash = new bytes(20);
            for (uint256 i = 0; i < 20; i++) {
                scriptHash[i] = output.script[i + 2];
            }
            info.scriptPubKeyAsm = formatP2SHAsm(scriptHash);
            info.destinationAddress = formatP2SHAddress(scriptHash);

            // P2WPKH (v0): OP_0 <pubKeyHash>
        } else if (output.script.length == 22 && firstByte == 0x00 && uint8(output.script[1]) == 0x14) {
            info.scriptType = TYPE_V0_P2WPKH;
            // Extract the pub key hash (bytes 2-21)
            bytes memory pubKeyHash = new bytes(20);
            for (uint256 i = 0; i < 20; i++) {
                pubKeyHash[i] = output.script[i + 2];
            }
            info.scriptPubKeyAsm = formatV0P2WPKHAsm(pubKeyHash);
            info.destinationAddress = formatV0P2WPKHAddress(pubKeyHash);

            // P2WSH (v0): OP_0 <scriptHash>
        } else if (output.script.length == 34 && firstByte == 0x00 && uint8(output.script[1]) == 0x20) {
            info.scriptType = TYPE_V0_P2WSH;
            // Extract the script hash (bytes 2-33)
            bytes memory scriptHash = new bytes(32);
            for (uint256 i = 0; i < 32; i++) {
                scriptHash[i] = output.script[i + 2];
            }
            info.scriptPubKeyAsm = formatV0P2WSHAsm(scriptHash);
            info.destinationAddress = formatV0P2WSHAddress(scriptHash);

            // P2TR (v1): OP_1 <x-only pubkey>
        } else if (output.script.length == 34 && firstByte == 0x51 && uint8(output.script[1]) == 0x20) {
            info.scriptType = TYPE_V1_P2TR;
            // Extract the x-only pubkey (bytes 2-33)
            bytes memory pubKey = new bytes(32);
            for (uint256 i = 0; i < 32; i++) {
                pubKey[i] = output.script[i + 2];
            }
            info.scriptPubKeyAsm = formatV1P2TRAsm(pubKey);
            info.destinationAddress = formatV1P2TRAddress(pubKey);

            // Unknown script type
        } else {
            info.scriptType = bytes32("unknown");
            info.scriptPubKeyAsm = formatUnknownAsm(output.script);
            info.destinationAddress = "";
        }

        return info;
    }

    /// @notice Formats assembly representation for P2PKH scripts
    /// @param pubKeyHash The public key hash
    /// @return asm The assembly string
    function formatP2PKHAsm(bytes memory pubKeyHash) internal pure returns (string memory asm) {
        return
            string(abi.encodePacked("OP_DUP OP_HASH160 ", bytesToHexString(pubKeyHash), " OP_EQUALVERIFY OP_CHECKSIG"));
    }

    /// @notice Formats a P2PKH address from a public key hash
    /// @param pubKeyHash The public key hash
    /// @return address The formatted address string
    function formatP2PKHAddress(bytes memory pubKeyHash) internal pure returns (string memory) {
        // In a real implementation, this would include base58 encoding with proper network prefix
        // Simplified version for demonstration
        return string(abi.encodePacked("1", bytesToHexString(pubKeyHash)));
    }

    /// @notice Formats assembly representation for P2SH scripts
    /// @param scriptHash The script hash
    /// @return asm The assembly string
    function formatP2SHAsm(bytes memory scriptHash) internal pure returns (string memory asm) {
        return string(abi.encodePacked("OP_HASH160 ", bytesToHexString(scriptHash), " OP_EQUAL"));
    }

    /// @notice Formats a P2SH address from a script hash
    /// @param scriptHash The script hash
    /// @return address The formatted address string
    function formatP2SHAddress(bytes memory scriptHash) internal pure returns (string memory) {
        // In a real implementation, this would include base58 encoding with proper network prefix
        // Simplified version for demonstration
        return string(abi.encodePacked("3", bytesToHexString(scriptHash)));
    }

    /// @notice Formats assembly representation for v0 P2WPKH scripts
    /// @param pubKeyHash The public key hash
    /// @return asm The assembly string
    function formatV0P2WPKHAsm(bytes memory pubKeyHash) internal pure returns (string memory asm) {
        return string(abi.encodePacked("OP_0 OP_PUSHBYTES_20 ", bytesToHexString(pubKeyHash)));
    }

    /// @notice Formats a v0 P2WPKH address (Bech32) from a public key hash
    /// @param pubKeyHash The public key hash
    /// @return address The formatted address string
    function formatV0P2WPKHAddress(bytes memory pubKeyHash) internal pure returns (string memory) {
        // In a real implementation, this would include bech32 encoding
        // Simplified version for demonstration purposes
        return string(abi.encodePacked("tb1", bytesToHexString(pubKeyHash)));
    }

    /// @notice Formats assembly representation for v0 P2WSH scripts
    /// @param scriptHash The script hash
    /// @return asm The assembly string
    function formatV0P2WSHAsm(bytes memory scriptHash) internal pure returns (string memory asm) {
        return string(abi.encodePacked("OP_0 OP_PUSHBYTES_32 ", bytesToHexString(scriptHash)));
    }

    /// @notice Formats a v0 P2WSH address (Bech32) from a script hash
    /// @param scriptHash The script hash
    /// @return address The formatted address string
    function formatV0P2WSHAddress(bytes memory scriptHash) internal pure returns (string memory) {
        // In a real implementation, this would include bech32 encoding
        // Simplified version for demonstration purposes
        return string(abi.encodePacked("tb1", bytesToHexString(scriptHash)));
    }

    /// @notice Formats assembly representation for v1 P2TR (Taproot) scripts
    /// @param pubKey The x-only public key
    /// @return asm The assembly string
    function formatV1P2TRAsm(bytes memory pubKey) internal pure returns (string memory asm) {
        return string(abi.encodePacked("OP_PUSHNUM_1 OP_PUSHBYTES_32 ", bytesToHexString(pubKey)));
    }

    /// @notice Formats a v1 P2TR address (Bech32m) from an x-only public key
    /// @param pubKey The x-only public key
    /// @return address The formatted address string
    function formatV1P2TRAddress(bytes memory pubKey) internal pure returns (string memory) {
        // In a real implementation, this would include bech32m encoding
        // Simplified version for demonstration purposes
        return string(abi.encodePacked("tb1p", bytesToHexString(pubKey)));
    }

    /// @notice Formats assembly representation for unknown script types
    /// @param script The script bytes
    /// @return asm The assembly string
    function formatUnknownAsm(bytes memory script) internal pure returns (string memory asm) {
        return bytesToHexString(script);
    }

    /// @notice Formats assembly representation for OP_RETURN scripts
    /// @param script The script bytes
    /// @return asm The assembly string
    function formatOpReturnAsm(bytes memory script) internal pure returns (string memory asm) {
        bytes memory data = extractOpReturnData(script);
        return string(abi.encodePacked("OP_RETURN OP_PUSHBYTES_", uint2str(data.length), " ", bytesToHexString(data)));
    }

    // /// @notice Extracts data from an OP_RETURN output script
    // /// @param script The script containing the OP_RETURN and data
    // /// @return data The extracted data
    function extractOpReturnData(bytes memory script) internal pure returns (bytes memory data) {
        if (script.length < 2 || script[0] != 0x6a) {
            revert INVALID_OP_RETURN_OUTPUT();
        }

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

        if (script.length < dataStart + dataLength) {
            revert INVALID_OP_RETURN_DATA_LENGTH();
        }

        data = new bytes(dataLength);
        for (uint256 i = 0; i < dataLength; i++) {
            data[i] = script[dataStart + i];
        }

        return data;
    }

    /// @notice Decodes metadata from OP_RETURN data into a structured format
    /// @param data The raw metadata bytes from OP_RETURN output
    /// @return Structured metadata containing receiver address, locked Amount, chain ID, and base token amount
    /// @dev Uses assembly for efficient byte manipulation and data extraction
    function decodeMetadata(bytes memory data) public pure returns (TransactionMetadata memory) {
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

    // /// @notice Extracts OP_RETURN data from a raw Bitcoin transaction
    // /// @param rawTxn The raw Bitcoin transaction bytes
    // /// @return bytes The extracted OP_RETURN data
    // /// @dev Searches through transaction outputs for OP_RETURN (0x6a) and handles different push operations
    // function extractOpReturnData(bytes memory rawTxn)
    //     public
    //     pure
    //     returns (bytes memory)
    // {
    //     Transaction memory txn = parseTransaction(rawTxn);

    //     // Find OP_RETURN output
    //     for (uint256 i = 0; i < txn.outputs.length; i++) {
    //         if (txn.outputs[i].script.length > 0 && txn.outputs[i].script[0] == 0x6a) {
    //             return extractOpReturnData(txn.outputs[i].script);
    //         }
    //     }

    //     revert NO_OP_RETURN_FOUND();
    // }

    /// @notice Find an output by its script type and return its details
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @param scriptType The script type to search for (e.g., "v0_p2wpkh")
    /// @return The matching output information or reverts if not found
    function findOutputByType(bytes memory rawTxn, bytes32 scriptType) public pure returns (OutputInfo memory) {
        OutputInfo[] memory outputs = parseTransactionOutputs(rawTxn);

        for (uint256 i = 0; i < outputs.length; i++) {
            if (outputs[i].scriptType == scriptType) {
                return outputs[i];
            }
        }

        revert UNSUPPORTED_SCRIPT_TYPE();
    }

    /// @notice Find an output by its public key hash and return its details
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @param pubKeyHash The public key hash to search for
    /// @return The matching output information or reverts if not found
    function findOutputByPubKeyHash(bytes memory rawTxn, bytes memory pubKeyHash)
        public
        pure
        returns (OutputInfo memory)
    {
        OutputInfo[] memory outputs = parseTransactionOutputs(rawTxn);

        for (uint256 i = 0; i < outputs.length; i++) {
            // For P2PKH and P2WPKH outputs, check if the pubKeyHash matches
            if (
                (outputs[i].scriptType == TYPE_P2PKH || outputs[i].scriptType == TYPE_V0_P2WPKH)
                    && containsPubKeyHash(outputs[i].scriptPubKey, pubKeyHash)
            ) {
                return outputs[i];
            }
        }

        revert UNSUPPORTED_SCRIPT_TYPE();
    }

    /// @notice Checks if a script contains a given public key hash
    /// @param script The script to check
    /// @param pubKeyHash The public key hash to look for
    /// @return True if the script contains the pubKeyHash
    function containsPubKeyHash(bytes memory script, bytes memory pubKeyHash) internal pure returns (bool) {
        if (script.length == 0 || pubKeyHash.length == 0) {
            return false;
        }

        uint8 firstByte = uint8(script[0]);

        // P2PKH: pubKeyHash starts at offset 3
        if (script.length == 25 && firstByte == 0x76 && uint8(script[1]) == 0xa9) {
            return compareBytes(script, 3, pubKeyHash, 0, pubKeyHash.length);
        }

        // P2WPKH: pubKeyHash starts at offset 2
        if (script.length == 22 && firstByte == 0x00 && uint8(script[1]) == 0x14) {
            return compareBytes(script, 2, pubKeyHash, 0, pubKeyHash.length);
        }

        return false;
    }

    /// @notice Compares two byte arrays starting at specific offsets
    /// @param a First byte array
    /// @param aOffset Offset into the first array
    /// @param b Second byte array
    /// @param bOffset Offset into the second array
    /// @param length Number of bytes to compare
    /// @return True if the bytes match
    function compareBytes(bytes memory a, uint256 aOffset, bytes memory b, uint256 bOffset, uint256 length)
        internal
        pure
        returns (bool)
    {
        if (a.length < aOffset + length || b.length < bOffset + length) {
            return false;
        }

        for (uint256 i = 0; i < length; i++) {
            if (a[aOffset + i] != b[bOffset + i]) {
                return false;
            }
        }

        return true;
    }

    /// @notice Helper function to convert bytes to hexadecimal string
    /// @param data The bytes to convert
    /// @return result The hexadecimal string
    function bytesToHexString(bytes memory data) internal pure returns (string memory result) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory hexString = new bytes(2 * data.length);

        for (uint256 i = 0; i < data.length; i++) {
            uint8 value = uint8(data[i]);
            hexString[i * 2] = hexChars[uint8(value >> 4)];
            hexString[i * 2 + 1] = hexChars[uint8(value & 0x0f)];
        }

        return string(hexString);
    }

    /// @notice Helper function to convert uint to string
    /// @param _i The uint value to convert
    /// @return result The string representation
    function uint2str(uint256 _i) internal pure returns (string memory result) {
        if (_i == 0) {
            return "0";
        }

        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }

        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }

        return string(bstr);
    }

    /// @notice Helper function to extract bytes from calldata
    /// @param data Source calldata bytes
    /// @param start Starting position in the source data
    /// @param length Number of bytes to extract
    /// @return result The extracted bytes
    function extractBytes(bytes memory data, uint256 start, uint256 length) public pure returns (bytes memory result) {
        result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    /// @notice Parses a raw Bitcoin transaction into a structured format
    /// @param rawTxn The raw Bitcoin transaction bytes
    /// @return txn Structured transaction data containing version, outputs, and locktime
    function parseTransaction(bytes memory rawTxn) public pure returns (Transaction memory txn) {
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

        // Skip inputs
        for (uint256 i = 0; i < inputCount; i++) {
            offset += 36; // Previous output (32 + 4)

            // Script length (VarInt)
            (uint256 scriptLength, uint256 scriptLengthSize) = parseVarInt(rawTxn, offset);
            offset += scriptLengthSize + scriptLength;

            offset += 4; // Sequence
        }

        // Parse output count (VarInt)
        (uint256 outputCount, uint256 outputCountSize) = parseVarInt(rawTxn, offset);
        offset += outputCountSize;

        // Parse outputs
        txn.outputs = new Output[](outputCount);
        for (uint256 i = 0; i < outputCount; i++) {
            // Value (8 bytes)
            bytes memory valueBytes = extractBytes(rawTxn, offset, 8);
            txn.outputs[i].value = uint64(bytes8(valueBytes));
            offset += 8;

            // Script length (VarInt)
            (uint256 scriptLength, uint256 scriptLengthSize) = parseVarInt(rawTxn, offset);
            offset += scriptLengthSize;

            // Script
            txn.outputs[i].script = extractBytes(rawTxn, offset, scriptLength);
            offset += scriptLength;
        }

        // Skip witness data
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
    function parseVarInt(bytes memory data, uint256 offset) public pure returns (uint256 value, uint256 consumed) {
        if (data.length < offset + 1) revert INVALID_VAR_INT_FORMAT();
        uint8 first = uint8(data[offset]);

        if (first < 0xfd) {
            return (first, 1);
        } else if (first == 0xfd) {
            if (data.length < offset + 3) revert INVALID_VAR_INT_FORMAT();
            bytes memory lengthBytes = extractBytes(data, offset + 1, 2);
            return (uint16(bytes2(lengthBytes)), 3);
        } else if (first == 0xfe) {
            if (data.length < offset + 5) revert INVALID_VAR_INT_FORMAT();
            bytes memory lengthBytes = extractBytes(data, offset + 1, 4);
            return (uint32(bytes4(lengthBytes)), 5);
        } else {
            if (data.length < offset + 9) revert INVALID_VAR_INT_FORMAT();
            bytes memory lengthBytes = extractBytes(data, offset + 1, 8);
            return (uint64(bytes8(lengthBytes)), 9);
        }
    }
}
