// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.28;

// import {BitcoinUtils} from "./BitcoinUtils.sol";
// import {BitcoinTxnParser} from "./BitcoinTxnParser.sol";

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
//         // 1. Calculate hashPrevouts, hashSequence, hashOutputs
//         bytes32 hashPrevouts = calculateHashPrevouts(rawTx);
//         bytes32 hashSequence = calculateHashSequence(rawTx);
//         bytes32 hashOutputs = calculateHashOutputs(rawTx);

//         // 2. Get input details
//         BitcoinTxnParser.Transaction memory txn = BitcoinTxnParser.parseTransaction(rawTx);

//         // 3. Construct the script code (P2WPKH)
//         bytes memory scriptCode = constructP2WPKHScriptCode(txn, inputIndex);

//         // 4. Build signing message (BIP143)
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

//         // 5. Double SHA256 the message
//         bytes32 messageHash = BitcoinUtils.sha256DoubleHash(message);

//         // 6. Verify ECDSA signature
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

//     /// @notice Verifies an ECDSA signature using the k256 precompile
//     function verifyECDSASignature(bytes32 messageHash, bytes memory signature, bytes memory pubKey)
//         internal
//         view
//         returns (bool)
//     {
//         // Use ecrecover precompile
//         (bytes32 r, bytes32 s, uint8 v) = parseSignature(signature);

//         address recovered = ecrecover(messageHash, v, r, s);
//         address expected = address(uint160(uint256(keccak256(pubKey))));

//         return recovered == expected;
//     }

//     /// @notice Helper to parse DER signature into r, s, v components
//     function parseSignature(bytes memory signature) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
//         require(signature.length == 65, "Invalid signature length");

//         assembly {
//             r := mload(add(signature, 32))
//             s := mload(add(signature, 64))
//             v := byte(0, mload(add(signature, 96)))
//         }

//         // Adjust v for ethereum's ecrecover
//         v = v + 27;
//     }

//     /// @notice Extracts outpoint (txid + vout) from transaction input
//     /// @param txn Parsed transaction
//     /// @param index Input index
//     /// @return Serialized outpoint (36 bytes)
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

//     /// @notice Extracts sequence number from transaction input
//     /// @param txn Parsed transaction
//     /// @param index Input index
//     /// @return Sequence number as bytes (4 bytes)
//     function getTxInSequence(BitcoinTxnParser.Transaction memory txn, uint256 index)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         require(index < txn.inputs.length, "Input index out of bounds");

//         return abi.encodePacked(txn.inputs[index].sequence);
//     }

//     /// @notice Extracts signature from witness data
//     /// @dev Expects P2WPKH witness format: [signature, pubkey]
//     /// @param txn Parsed transaction
//     /// @param index Input index
//     /// @return DER-encoded signature with sighash type
//     function getWitnessSignature(BitcoinTxnParser.Transaction memory txn, uint256 index)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         require(index < txn.inputs.length, "Input index out of bounds");
//         require(txn.inputs[index].witness.length == 2, "Invalid P2WPKH witness");

//         bytes memory signature = txn.inputs[index].witness[0];
//         require(signature.length >= 64, "Invalid signature length"); // DER signature + sighash byte

//         // Remove sighash byte and return
//         return BytesLib.slice(signature, 0, signature.length - 1);
//     }

//     /// @notice Extracts public key from witness data
//     /// @dev Expects P2WPKH witness format: [signature, pubkey]
//     /// @param txn Parsed transaction
//     /// @param index Input index
//     /// @return Compressed public key (33 bytes)
//     function getWitnessPublicKey(BitcoinTxnParser.Transaction memory txn, uint256 index)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         require(index < txn.inputs.length, "Input index out of bounds");
//         require(txn.inputs[index].witness.length == 2, "Invalid P2WPKH witness");

//         bytes memory pubKey = txn.inputs[index].witness[1];
//         require(pubKey.length == 33, "Invalid public key length"); // Must be compressed

//         return pubKey;
//     }
// }

// /// @notice Helper library for byte manipulation
// library BytesLib {
//     /// @notice Extracts a slice of an array of bytes
//     /// @param _bytes Source bytes
//     /// @param _start Start index
//     /// @param _length Length to extract
//     /// @return result Extracted bytes
//     function slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
//         require(_length + 31 >= _length, "slice_overflow");
//         require(_bytes.length >= _start + _length, "slice_outOfBounds");

//         bytes memory tempBytes;
//         assembly {
//             switch iszero(_length)
//             case 0 {
//                 // Get a location of some free memory and store it in tempBytes as
//                 // Solidity does for memory variables.
//                 tempBytes := mload(0x40)

//                 // The first word of the slice result is potentially not fully used.
//                 // To ensure correctness, we calculate the length mod 32 and add it
//                 // to the offset. We can safely add it to the offset because of the
//                 // overflow check above.
//                 let lengthmod := and(_length, 31)

//                 // tempBytes = tempBytes + length + lengthmod
//                 let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
//                 let end := add(mc, _length)

//                 for {
//                     // The multiplication in the next line has the same exact purpose
//                     // as the one above.
//                     let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
//                 } lt(mc, end) {
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
