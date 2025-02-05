// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.28;

// import {BitcoinUtils} from "./BitcoinUtils.sol";

// /// @title BitcoinTxnParser
// /// @notice Library for parsing Bitcoin transactions
// library BitcoinTxnParser {
//     using BitcoinUtils for *;

//     // Custom errors
//     error INVALID_OP_RETURN_OUTPUT();
//     error UNSUPPORTED_PUSH_OPERATION();
//     error INVALID_PUSH_DATA_1();
//     error INVALID_PUSH_DATA_2();
//     error INVALID_OP_RETURN_DATA_LENGTH();
//     error NO_OP_RETURN_FOUND();
//     error INVALID_TRANSACTION_FORMAT();
//     error INVALID_VAR_INT_FORMAT();

//     struct Input {
//         bytes32 txid; // Previous transaction ID
//         uint32 vout; // Previous output index
//         bytes script; // ScriptSig
//         uint32 sequence; // Sequence number
//         bytes[] witness; // Witness data (for SegWit)
//     }

//     struct Output {
//         uint64 value;
//         bytes script;
//     }

//     struct Transaction {
//         uint32 version;
//         Input[] inputs;
//         Output[] outputs;
//         uint32 locktime;
//         bool hasWitness;
//     }

//     struct TransactionMetadata {
//         address receiverAddress;
//         uint256 lockedAmount;
//         uint32 chainId;
//         uint256 nativeTokenAmount;
//     }

//     /// @notice Helper function to extract bytes from memory
//     function extractBytes(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
//         bytes memory result = new bytes(length);
//         for (uint256 i = 0; i < length; i++) {
//             result[i] = data[start + i];
//         }
//         return result;
//     }

//     /// @notice Parse variable integer
//     function parseVarInt(bytes memory data, uint256 offset) internal pure returns (uint256 value, uint256 consumed) {
//         require(data.length >= offset + 1, "INVALID_VAR_INT_FORMAT");
//         uint8 first = uint8(data[offset]);

//         if (first < 0xfd) {
//             return (first, 1);
//         } else if (first == 0xfd) {
//             require(data.length >= offset + 3, "INVALID_VAR_INT_FORMAT");
//             return (uint16(uint8(data[offset + 1])) | (uint16(uint8(data[offset + 2])) << 8), 3);
//         } else if (first == 0xfe) {
//             require(data.length >= offset + 5, "INVALID_VAR_INT_FORMAT");
//             return (
//                 uint32(uint8(data[offset + 1])) | (uint32(uint8(data[offset + 2])) << 8)
//                     | (uint32(uint8(data[offset + 3])) << 16) | (uint32(uint8(data[offset + 4])) << 24),
//                 5
//             );
//         } else {
//             require(data.length >= offset + 9, "INVALID_VAR_INT_FORMAT");
//             return (
//                 uint64(uint8(data[offset + 1])) | (uint64(uint8(data[offset + 2])) << 8)
//                     | (uint64(uint8(data[offset + 3])) << 16) | (uint64(uint8(data[offset + 4])) << 24)
//                     | (uint64(uint8(data[offset + 5])) << 32) | (uint64(uint8(data[offset + 6])) << 40)
//                     | (uint64(uint8(data[offset + 7])) << 48) | (uint64(uint8(data[offset + 8])) << 56),
//                 9
//             );
//         }
//     }

//     /// @notice Parse inputs from raw transaction bytes
//     function parseInputs(bytes memory rawTx, uint256 offset)
//         internal
//         pure
//         returns (Input[] memory inputs, uint256 newOffset)
//     {
//         (uint256 inputCount, uint256 countSize) = parseVarInt(rawTx, offset);
//         offset += countSize;

//         inputs = new Input[](inputCount);

//         for (uint256 i = 0; i < inputCount; i++) {
//             // Parse txid (32 bytes)
//             bytes32 txid;
//             assembly {
//                 txid := mload(add(add(rawTx, 32), offset))
//             }
//             offset += 32;

//             // Parse vout (4 bytes)
//             bytes memory voutBytes = extractBytes(rawTx, offset, 4);
//             uint32 vout;
//             assembly {
//                 vout := mload(add(voutBytes, 32))
//             }
//             offset += 4;

//             // Parse script
//             (uint256 scriptLen, uint256 scriptLenSize) = parseVarInt(rawTx, offset);
//             offset += scriptLenSize;
//             bytes memory script = extractBytes(rawTx, offset, scriptLen);
//             offset += scriptLen;

//             // Parse sequence (4 bytes)
//             bytes memory seqBytes = extractBytes(rawTx, offset, 4);
//             uint32 sequence;
//             assembly {
//                 sequence := mload(add(seqBytes, 32))
//             }
//             offset += 4;

//             inputs[i] = Input({txid: txid, vout: vout, script: script, sequence: sequence, witness: new bytes[](0)});
//         }

//         newOffset = offset;
//     }

//     /// @notice Parse witness data for SegWit transactions
//     function parseWitness(bytes memory rawTx, uint256 offset, Input storage input)
//         internal
//         pure
//         returns (uint256 newOffset)
//     {
//         (uint256 witnessCount, uint256 countSize) = parseVarInt(rawTx, offset);
//         offset += countSize;

//         delete input.witness;
//         input.witness = new bytes[](witnessCount);

//         for (uint256 i = 0; i < witnessCount; i++) {
//             (uint256 witnessLen, uint256 witnessLenSize) = parseVarInt(rawTx, offset);
//             offset += witnessLenSize;

//             input.witness[i] = extractBytes(rawTx, offset, witnessLen);
//             offset += witnessLen;
//         }

//         return offset;
//     }

//     /// @notice Parse outputs from raw transaction bytes
//     function parseOutputs(bytes memory rawTx, uint256 offset)
//         internal
//         pure
//         returns (Output[] memory outputs, uint256 newOffset)
//     {
//         (uint256 outputCount, uint256 countSize) = parseVarInt(rawTx, offset);
//         offset += countSize;

//         outputs = new Output[](outputCount);

//         for (uint256 i = 0; i < outputCount; i++) {
//             // Parse value (8 bytes)
//             bytes memory valueBytes = extractBytes(rawTx, offset, 8);
//             uint64 value;
//             assembly {
//                 value := mload(add(valueBytes, 32))
//             }
//             offset += 8;

//             // Parse script
//             (uint256 scriptLen, uint256 scriptLenSize) = parseVarInt(rawTx, offset);
//             offset += scriptLenSize;
//             bytes memory script = extractBytes(rawTx, offset, scriptLen);
//             offset += scriptLen;

//             outputs[i] = Output({value: value, script: script});
//         }

//         newOffset = offset;
//     }

//     /// @notice Parse complete transaction
//     function parseTransaction(bytes memory rawTx) internal pure returns (Transaction memory txn) {
//         uint256 offset = 0;

//         // Parse version
//         bytes memory versionBytes = extractBytes(rawTx, offset, 4);
//         txn.version = uint32(uint256(bytes32(versionBytes)));
//         offset += 4;

//         // Check for SegWit
//         txn.hasWitness = false;
//         if (rawTx.length > offset + 1 && rawTx[offset] == 0x00 && rawTx[offset + 1] == 0x01) {
//             txn.hasWitness = true;
//             offset += 2;
//         }

//         // Parse inputs
//         (Input[] memory inputs, uint256 newOffset) = parseInputs(rawTx, offset);
//         txn.inputs = inputs;
//         offset = newOffset;

//         // Parse outputs
//         (Output[] memory outputs, uint256 outOffset) = parseOutputs(rawTx, offset);
//         txn.outputs = outputs;
//         offset = outOffset;

//         // Parse witness data if present
//         if (txn.hasWitness) {
//             for (uint256 i = 0; i < txn.inputs.length; i++) {
//                 offset = parseWitness(rawTx, offset, txn.inputs[i]);
//             }
//         }

//         // Parse locktime
//         require(rawTx.length >= offset + 4, "Invalid transaction format");
//         bytes memory locktimeBytes = extractBytes(rawTx, offset, 4);
//         txn.locktime = uint32(uint256(bytes32(locktimeBytes)));
//     }
// }
