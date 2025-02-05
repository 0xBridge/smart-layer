// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.28;

// import {BitcoinUtils} from "./BitcoinUtils.sol";
// import {BitcoinTxnParser} from "./BitcoinTxnParser.sol";

// /// @title SegWitVerifier
// /// @notice Library for verifying SegWit signatures
// library SegWitVerifier {
//     using BitcoinUtils for *;
//     using BitcoinTxnParser for *;

//     struct PrevOutput {
//         uint64 value;
//         bytes scriptPubKey;
//     }

//     error INVALID_WITNESS_PROGRAM();
//     error INVALID_SIGNATURE_LENGTH();
//     error SIGNATURE_VERIFICATION_FAILED();

//     /// @notice Verifies a SegWit signature for P2WPKH
//     /// @param rawTx Raw transaction bytes
//     /// @param inputIndex Index of input being verified
//     /// @param prevOutputs Array of previous output information
//     /// @return True if signature is valid
//     function verifySegwitSignature(bytes memory rawTx, uint256 inputIndex, PrevOutput[] memory prevOutputs)
//         internal
//         view
//         returns (bool)
//     {
//         // Parse transaction
//         BitcoinTxnParser.Transaction memory txn = BitcoinTxnParser.parseTransaction(rawTx);
//         require(txn.hasWitness, "Not a SegWit transaction");
//         require(inputIndex < txn.inputs.length, "Input index out of bounds");

//         // 1. Calculate hashPrevouts, hashSequence, hashOutputs
//         bytes32 hashPrevouts = calculateHashPrevouts(rawTx);
//         bytes32 hashSequence = calculateHashSequence(rawTx);
//         bytes32 hashOutputs = calculateHashOutputs(rawTx);

//         // 2. Construct the script code (P2WPKH)
//         bytes memory scriptCode = constructP2WPKHScriptCode(txn, inputIndex);

//         // 3. Build signing message (BIP143)
//         bytes memory message = abi.encodePacked(
//             txn.version,
//             hashPrevouts,
//             hashSequence,
//             // outpoint (txid + index)
//             getTxInOutpoint(txn, inputIndex),
//             scriptCode,
//             prevOutputs[inputIndex].value,
//             getTxInSequence(txn, inputIndex),
//             hashOutputs,
//             txn.locktime,
//             uint32(1) // SIGHASH_ALL
//         );

//         // 4. Double SHA256 the message
//         bytes32 messageHash = BitcoinUtils.sha256DoubleHash(message);

//         // 5. Verify ECDSA signature
//         return verifyECDSASignature(
//             messageHash, getWitnessSignature(txn, inputIndex), getWitnessPublicKey(txn, inputIndex)
//         );
//     }

//     /// @notice Calculates double SHA256 hash of all outpoints
//     function calculateHashPrevouts(bytes memory rawTx) internal view returns (bytes32) {
//         BitcoinTxnParser.Transaction memory txn = BitcoinTxnParser.parseTransaction(rawTx);
//         bytes memory prevouts;

//         for (uint256 i = 0; i < txn.inputs.length; i++) {
//             prevouts = bytes.concat(prevouts, getTxInOutpoint(txn, i));
//         }

//         return BitcoinUtils.sha256DoubleHash(prevouts);
//     }

//     /// @notice Calculates double SHA256 hash of all sequence numbers
//     function calculateHashSequence(bytes memory rawTx) internal view returns (bytes32) {
//         BitcoinTxnParser.Transaction memory txn = BitcoinTxnParser.parseTransaction(rawTx);
//         bytes memory sequences;

//         for (uint256 i = 0; i < txn.inputs.length; i++) {
//             sequences = bytes.concat(sequences, getTxInSequence(txn, i));
//         }

//         return BitcoinUtils.sha256DoubleHash(sequences);
//     }

//     /// @notice Calculates double SHA256 hash of all outputs
//     function calculateHashOutputs(bytes memory rawTx) internal view returns (bytes32) {
//         BitcoinTxnParser.Transaction memory txn = BitcoinTxnParser.parseTransaction(rawTx);
//         bytes memory outputs;

//         for (uint256 i = 0; i < txn.outputs.length; i++) {
//             outputs = bytes.concat(outputs, abi.encodePacked(txn.outputs[i].value), txn.outputs[i].script);
//         }

//         return BitcoinUtils.sha256DoubleHash(outputs);
//     }

//     /// @notice Constructs P2WPKH script code from public key
//     function constructP2WPKHScriptCode(BitcoinTxnParser.Transaction memory txn, uint256 inputIndex)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         bytes memory pubKey = getWitnessPublicKey(txn, inputIndex);
//         bytes20 pubKeyHash = ripemd160(abi.encodePacked(sha256(pubKey)));

//         return abi.encodePacked(
//             hex"76a914", // OP_DUP OP_HASH160 PUSH20
//             pubKeyHash,
//             hex"88ac" // OP_EQUALVERIFY OP_CHECKSIG
//         );
//     }

//     /// @notice Helper to get outpoint from transaction input
//     function getTxInOutpoint(BitcoinTxnParser.Transaction memory txn, uint256 index)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         require(index < txn.inputs.length, "Input index out of bounds");

//         return bytes.concat(
//             txn.inputs[index].txid, // Previous txid (32 bytes)
//             abi.encodePacked( // Previous vout (4 bytes)
//             txn.inputs[index].vout)
//         );
//     }

//     /// @notice Helper to get sequence from transaction input
//     function getTxInSequence(BitcoinTxnParser.Transaction memory txn, uint256 index)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         require(index < txn.inputs.length, "Input index out of bounds");
//         return abi.encodePacked(txn.inputs[index].sequence);
//     }

//     /// @notice Helper to get witness signature
//     function getWitnessSignature(BitcoinTxnParser.Transaction memory txn, uint256 index)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         require(index < txn.inputs.length, "Input index out of bounds");
//         require(txn.inputs[index].witness.length >= 2, "Invalid witness stack");

//         bytes memory signature = txn.inputs[index].witness[0];
//         require(signature.length >= 64, "Invalid signature length");

//         // Remove sighash byte
//         return BytesLib.slice(signature, 0, signature.length - 1);
//     }

//     /// @notice Helper to get witness public key
//     function getWitnessPublicKey(BitcoinTxnParser.Transaction memory txn, uint256 index)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         require(index < txn.inputs.length, "Input index out of bounds");
//         require(txn.inputs[index].witness.length >= 2, "Invalid witness stack");

//         bytes memory pubKey = txn.inputs[index].witness[1];
//         require(pubKey.length == 33, "Invalid public key length");

//         return pubKey;
//     }

//     /// @notice Verifies ECDSA signature
//     function verifyECDSASignature(bytes32 messageHash, bytes memory signature, bytes memory pubKey)
//         internal
//         pure
//         returns (bool)
//     {
//         require(signature.length == 64, "Invalid signature length");
//         require(pubKey.length == 33, "Invalid public key length");

//         (bytes32 r, bytes32 s) = parseSignature(signature);

//         // Verify using ecrecover
//         address recovered = ecrecover(messageHash, 27, r, s);
//         if (recovered == address(0)) {
//             recovered = ecrecover(messageHash, 28, r, s);
//         }

//         address expected = address(uint160(uint256(keccak256(pubKey))));
//         return recovered == expected;
//     }

//     /// @notice Parses DER signature into r, s components
//     function parseSignature(bytes memory signature) internal pure returns (bytes32 r, bytes32 s) {
//         require(signature.length == 64, "Invalid signature length");

//         assembly {
//             r := mload(add(signature, 32))
//             s := mload(add(signature, 64))
//         }
//     }
// }

// /// @notice Helper library for byte manipulation
// library BytesLib {
//     function slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
//         require(_length + 31 >= _length, "slice_overflow");
//         require(_bytes.length >= _start + _length, "slice_outOfBounds");

//         bytes memory tempBytes;
//         assembly {
//             switch iszero(_length)
//             case 0 {
//                 tempBytes := mload(0x40)
//                 let lengthmod := and(_length, 31)
//                 let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
//                 let end := add(mc, _length)

//                 for { let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start) } lt(mc, end) {
//                     mc := add(mc, 0x20)
//                     cc := add(cc, 0x20)
//                 } { mstore(mc, mload(cc)) }

//                 mstore(tempBytes, _length)
//                 mstore(0x40, and(add(mc, 31), not(31)))
//             }
//             default {
//                 tempBytes := mload(0x40)
//                 mstore(tempBytes, 0)
//                 mstore(0x40, add(tempBytes, 0x20))
//             }
//         }

//         return tempBytes;
//     }
// }
