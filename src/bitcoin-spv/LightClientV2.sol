// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibSecp256k1} from "@solady/src/utils/LibSecp256k1.sol";

contract BitcoinLightClient {
    using LibSecp256k1 for bytes32;

    // Struct to represent a Bitcoin block header
    struct BlockHeader {
        bytes32 version;
        bytes32 prevBlockHash;
        bytes32 merkleRoot;
        uint32 timestamp;
        uint256 bits;
        uint32 nonce;
    }

    // Struct to represent a PSBT input
    struct PSBTInput {
        bytes32 prevTxId;
        uint32 outputIndex;
        bytes scriptSig;
        bytes32 pubKey;
        bytes32 signature;
        bytes witnessScript;
    }

    // Struct to represent a PSBT output
    struct PSBTOutput {
        bytes scriptPubKey;
        bytes redeemScript;
        bytes32 extendedPubKey;
    }

    // Mapping to store block headers by block height
    mapping(uint256 => BlockHeader) public blockHeaders;
    uint256 public latestBlockHeight;

    // Event to log new block headers
    event BlockHeaderAdded(uint256 blockHeight, bytes32 blockHash);

    // Add a new block header to the chain
    function addBlockHeader(
        bytes32 version,
        bytes32 prevBlockHash,
        bytes32 merkleRoot,
        uint32 timestamp,
        uint256 bits,
        uint32 nonce
    ) external {
        // Verify blockchain continuity
        if (latestBlockHeight > 0) {
            require(
                prevBlockHash == blockHeaders[latestBlockHeight - 1].prevBlockHash,
                "Invalid previous block hash"
            );
        }

        // Verify PoW
        bytes32 blockHash = computeBlockHash(version, prevBlockHash, merkleRoot, timestamp, bits, nonce);
        require(isValidPoW(blockHash, bits), "Invalid PoW");

        // Store the block header
        blockHeaders[latestBlockHeight] = BlockHeader(version, prevBlockHash, merkleRoot, timestamp, bits, nonce);
        emit BlockHeaderAdded(latestBlockHeight, blockHash);

        latestBlockHeight++;
    }

    // Verify transaction inclusion in a block
    function verifyTransactionInclusion(
        uint256 blockHeight,
        bytes32 txHash,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        BlockHeader storage header = blockHeaders[blockHeight];
        bytes32 computedRoot = computeMerkleRoot(txHash, merkleProof);
        return computedRoot == header.merkleRoot;
    }

    // Validate a PSBT and verify transaction inclusion
    function validatePSBTAndVerifyInclusion(
        bytes calldata psbt,
        uint256 blockHeight,
        bytes32 txHash,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        // Validate the PSBT
        (PSBTInput[] memory inputs, PSBTOutput[] memory outputs) = decodePSBT(psbt);
        require(inputs.length > 0, "No inputs in PSBT");
        require(outputs.length > 0, "No outputs in PSBT");

        for (uint256 i = 0; i < inputs.length; i++) {
            require(validateInput(inputs[i]), "Invalid input");
        }

        // Verify transaction inclusion
        return verifyTransactionInclusion(blockHeight, txHash, merkleProof);
    }

    // Decode a PSBT according to BIP-174
    function decodePSBT(bytes calldata psbt) internal pure returns (PSBTInput[] memory inputs, PSBTOutput[] memory outputs) {
        uint256 offset = 0;

        // Skip version (first 4 bytes)
        offset += 4;

        // Skip unsigned transaction (length-prefixed)
        uint256 unsignedTxLength = uint256(uint8(psbt[offset]));
        offset += 1 + unsignedTxLength;

        // Parse inputs
        uint256 inputCount = uint256(uint8(psbt[offset]));
        offset += 1;

        inputs = new PSBTInput[](inputCount);
        for (uint256 i = 0; i < inputCount; i++) {
            PSBTInput memory input;

            input.prevTxId = bytes32(psbt[offset:offset + 32]);
            offset += 32;

            input.outputIndex = uint32(bytes4(psbt[offset:offset + 4]));
            offset += 4;

            uint256 scriptSigLength = uint256(uint8(psbt[offset]));
            offset += 1;
            input.scriptSig = psbt[offset:offset + scriptSigLength];
            offset += scriptSigLength;

            input.pubKey = bytes32(psbt[offset:offset + 32]);
            offset += 32;

            input.signature = bytes32(psbt[offset:offset + 32]);
            offset += 32;

            uint256 witnessScriptLength = uint256(uint8(psbt[offset]));
            offset += 1;
            input.witnessScript = psbt[offset:offset + witnessScriptLength];
            offset += witnessScriptLength;

            inputs[i] = input;
        }

        // Parse outputs
        uint256 outputCount = uint256(uint8(psbt[offset]));
        offset += 1;

        outputs = new PSBTOutput[](outputCount);
        for (uint256 i = 0; i < outputCount; i++) {
            PSBTOutput memory output;

            uint256 scriptPubKeyLength = uint256(uint8(psbt[offset]));
            offset += 1;
            output.scriptPubKey = psbt[offset:offset + scriptPubKeyLength];
            offset += scriptPubKeyLength;

            uint256 redeemScriptLength = uint256(uint8(psbt[offset]));
            offset += 1;
            output.redeemScript = psbt[offset:offset + redeemScriptLength];
            offset += redeemScriptLength;

            output.extendedPubKey = bytes32(psbt[offset:offset + 32]);
            offset += 32;

            outputs[i] = output;
        }

        // Skip proprietary data (length-prefixed)
        uint256 proprietaryDataLength = uint256(uint8(psbt[offset]));
        offset += 1 + proprietaryDataLength;
    }

    // Validate a PSBT input
    function validateInput(PSBTInput memory input) internal pure returns (bool) {
        bytes32 message = sha256(abi.encodePacked(input.prevTxId, input.outputIndex));
        (bool success, bytes32 recoveredPubKey) = LibSecp256k1.ecdsaRecover(message, input.signature);
        require(success, "Signature recovery failed");
        return recoveredPubKey == input.pubKey;
    }

    // Compute block hash
    function computeBlockHash(
        bytes32 version,
        bytes32 prevBlockHash,
        bytes32 merkleRoot,
        uint32 timestamp,
        uint256 bits,
        uint32 nonce
    ) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(version, prevBlockHash, merkleRoot, timestamp, bits, nonce));
    }

    // Verify PoW
    function isValidPoW(bytes32 blockHash, uint256 bits) internal pure returns (bool) {
        uint256 target = (1 << (256 - bits)) - 1;
        return uint256(blockHash) <= target;
    }

    // Compute Merkle root from a transaction hash and Merkle proof
    function computeMerkleRoot(bytes32 txHash, bytes32[] calldata merkleProof) internal pure returns (bytes32) {
        bytes32 computedHash = txHash;
        for (uint256 i = 0; i < merkleProof.length; i++) {
            bytes32 proofElement = merkleProof[i];
            if (computedHash < proofElement) {
                computedHash = sha256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = sha256(abi.encodePacked(proofElement, computedHash));
            }
        }
        return computedHash;
    }
}