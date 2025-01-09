// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library BitcoinSPV {
    struct BitcoinBlockHeader {
        uint32 version;
        bytes32 prevBlockHash;
        bytes32 merkleRoot;
        uint32 timestamp;
        uint32 bits;
        uint32 nonce;
    }

    // Difficulty target threshold for PoW verification
    function targetFromBits(uint32 bits) internal pure returns (uint256) {
        uint32 exponent = bits >> 24;
        uint32 coefficient = bits & 0xFFFFFF;
        uint256 target = uint256(coefficient) * 2**(8 * (exponent - 3));
        // Debug log
        require(target > 0, "Calculated target is zero");
        return target;
    }

    // Verify Proof of Work
    function verifyPoW(BitcoinBlockHeader memory header) internal pure returns (bool) {
        // Check for valid structure and values
        require(header.bits != 0, "Invalid bits");
        require(header.nonce != 0, "Invalid nonce");

        bytes32 headerHash = sha256(abi.encodePacked(sha256(abi.encodePacked(
            header.version,
            header.prevBlockHash,
            header.merkleRoot,
            header.timestamp,
            header.bits,
            header.nonce
        ))));

        uint256 target = targetFromBits(header.bits);
        require(target > 0 && target < type(uint256).max, "Invalid target");

        // Debug log
        require(uint256(headerHash) < target, "Proof of Work verification failed");

        return uint256(headerHash) < target;
    }

    // Verify Blockchain Continuity
    function verifyContinuity(
        bytes32 prevBlockHash,
        bytes32 currentBlockHash
    ) internal pure returns (bool) {
        // Debug log
        require(prevBlockHash != bytes32(0), "Previous block hash is zero");
        require(currentBlockHash != bytes32(0), "Current block hash is zero");
        return prevBlockHash == currentBlockHash;
    }

    // Verify Transaction Inclusion using Merkle Proof
    function verifyTransactionInclusion(
        bytes32 txHash,
        bytes32 merkleRoot,
        bytes32[] memory proof,
        uint256 index
    ) internal pure returns (bool) {
        require(proof.length > 0, "Proof cannot be empty");

        bytes32 hash = txHash;
        for (uint256 i = 0; i < proof.length; i++) {
            require(proof[i] != bytes32(0), "Invalid proof element");
            if (index % 2 == 0) {
                hash = sha256(abi.encodePacked(hash, proof[i]));
            } else {
                hash = sha256(abi.encodePacked(proof[i], hash));
            }
            index /= 2;

            // Debug log
            require(hash != bytes32(0), "Intermediate hash is zero");
        }
        require(hash == merkleRoot, "Transaction inclusion verification failed");
        return hash == merkleRoot;
    }
}

contract BitcoinSPVContract {
    using BitcoinSPV for BitcoinSPV.BitcoinBlockHeader;

    mapping(bytes32 => BitcoinSPV.BitcoinBlockHeader) public knownBlocks;
    bytes32 public genesisBlockHash;

    // Initialize the genesis block
    constructor(BitcoinSPV.BitcoinBlockHeader memory genesisBlock) {
        require(genesisBlock.verifyPoW(), "Invalid Genesis Block Proof of Work");
        genesisBlockHash = keccak256(abi.encodePacked(genesisBlock));
        knownBlocks[genesisBlockHash] = genesisBlock;

        // Debug log
        require(knownBlocks[genesisBlockHash].version != 0, "Genesis block not properly stored");
        require(genesisBlock.timestamp > 0, "Genesis block timestamp is invalid");
        require(genesisBlock.merkleRoot != bytes32(0), "Genesis block merkle root is invalid");
    }

    // Store a verified block
    function addBlock(BitcoinSPV.BitcoinBlockHeader memory header) public {
        require(header.verifyPoW(), "Invalid Proof of Work");
        require(
            knownBlocks[header.prevBlockHash].prevBlockHash != bytes32(0),
            "Parent block not known"
        );

        bytes32 blockHash = keccak256(abi.encodePacked(header));
        require(
            knownBlocks[blockHash].version == 0,
            "Block already added"
        );

        knownBlocks[blockHash] = header;

        // Debug log
        require(knownBlocks[blockHash].version != 0, "Block not properly stored");
    }

    // Verify a transaction inclusion
    function verifyTransaction(
        bytes32 txHash,
        bytes32 merkleRoot,
        bytes32[] memory proof,
        uint256 index
    ) public pure returns (bool) {
        bool result = BitcoinSPV.verifyTransactionInclusion(txHash, merkleRoot, proof, index);

        // Debug log
        require(result, "Transaction verification failed");
        return result;
    }
}
