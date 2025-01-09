// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BitcoinUtils} from "./lib/BitcoinUtils.sol";

contract BitcoinLightClient {
    // Error codes
    error INVALID_HEADER_LENGTH();
    error INVALID_PROOF_OF_WORK();
    error INVALID_HEADER_CHAIN();
    error CHAIN_NOT_CONNECTED();
    error INVALID_TRANSACTION_INDEX();

    // Role for submitting new block headers
    bytes32 private constant BLOCK_SUBMIT_ROLE = keccak256("BLOCK_SUBMIT_ROLE");
    // Length of a Bitcoin block header
    uint8 private constant HEADER_LENGTH = 80;

    // Latest checkpoint header hash
    bytes32 private latestCheckpointHeaderHash;

    // Mapping of block hash to block header
    mapping(bytes32 => BitcoinUtils.BlockHeader) private headers;

    // Event emitted when a new block header is submitted
    event BlockHeaderSubmitted(bytes32 indexed blockHash, bytes32 indexed prevBlock, uint32 height);

    constructor(
        uint32 version, // 4 bytes
        uint32 timestamp, // 4 bytes
        uint32 difficultyBits, // 4 bytes
        uint32 nonce, // 4 bytes
        uint32 height, // 4 bytes
        bytes32 prevBlock, // 32 bytes
        bytes32 merkleRoot // 32 bytes
    ) {
        BitcoinUtils.BlockHeader memory header =
            BitcoinUtils.BlockHeader(version, timestamp, difficultyBits, nonce, height, prevBlock, merkleRoot);
        latestCheckpointHeaderHash = BitcoinUtils.getBlockHashFromStruct(header);
        headers[latestCheckpointHeaderHash] = header;
    }

    /**
     * @notice Submit a new block header along with intermediate headers connecting to last checkpoint
     * @param rawHeader bytes header
     * @param intermediateHeaders Array of intermediate headers connecting to last checkpoint (in reverse order)
     * @dev intermediateHeaders should be ordered from newest to oldest (connecting to checkpoint)
     */
    function submitBlockHeader(bytes calldata rawHeader, bytes[] calldata intermediateHeaders)
        external
        returns (bool)
    {
        bytes32 blockHash = getBlockHash(rawHeader);
        BitcoinUtils.BlockHeader memory header = BitcoinUtils.parseBlockHeader(rawHeader);

        // Verify POW for new header
        if (!BitcoinUtils.verifyProofOfWork(blockHash, header.difficultyBits)) {
            revert INVALID_PROOF_OF_WORK();
        }

        // If there are intermediate headers, verify the continuity
        if (intermediateHeaders.length > 0) {
            bool isValid = verifyHeaderChain(header.prevBlock, intermediateHeaders);
            if (!isValid) revert INVALID_HEADER_CHAIN();
        } else {
            // If no intermediate headers, verify direct connection to checkpoint
            if (header.prevBlock != latestCheckpointHeaderHash) revert CHAIN_NOT_CONNECTED();
        }

        // Update the checkpoint
        uint32 latestHeaderHeight = headers[latestCheckpointHeaderHash].height;
        header.height = latestHeaderHeight + uint32(intermediateHeaders.length) + 1;
        latestCheckpointHeaderHash = blockHash;
        headers[latestCheckpointHeaderHash] = header;

        emit BlockHeaderSubmitted(blockHash, header.prevBlock, header.height);
        return true;
    }

    /**
     * @notice Verify a chain of headers connects properly from latest checkpoint to new block
     * @param currentPrevHash Previous hash of the current header
     * @param intermediateHeaders Array of intermediate headers
     * @return bool True if chain is valid
     */
    function verifyHeaderChain(bytes32 currentPrevHash, bytes[] calldata intermediateHeaders)
        public
        view
        returns (bool)
    {
        // Verify each intermediate header
        for (uint256 i = 0; i < intermediateHeaders.length; i++) {
            // Parse and verify the header
            BitcoinUtils.BlockHeader memory intermediateHeader = BitcoinUtils.parseBlockHeader(intermediateHeaders[i]);

            // Calculate hash of this intermediate header
            bytes32 intermediateHash = BitcoinUtils.sha256DoubleHash(intermediateHeaders[i]);
            intermediateHash = BitcoinUtils.reverseBytes32(intermediateHash);

            // Verify the hash chain
            if (currentPrevHash != intermediateHash) revert INVALID_HEADER_CHAIN();

            // Verify POW for intermediate header
            if (!BitcoinUtils.verifyProofOfWork(intermediateHash, intermediateHeader.difficultyBits)) {
                revert INVALID_PROOF_OF_WORK();
            }

            // Move to next header
            currentPrevHash = intermediateHeader.prevBlock;
        }

        // Final verification - connect to checkpoint
        return currentPrevHash == latestCheckpointHeaderHash; // Evaluate till how many blocks does this not return OOG error
    }

    /**
     * @dev Calculate bitcoin block hash in reverse byte order
     * @param blockHeader Raw block header bytes
     * @return bytes32 Block hash in reverse byte order
     */
    function getBlockHash(bytes memory blockHeader) public view returns (bytes32) {
        require(blockHeader.length == HEADER_LENGTH, INVALID_HEADER_LENGTH());
        // First get the double SHA256 hash
        bytes32 hash = BitcoinUtils.sha256DoubleHash(blockHeader);

        // Then reverse it
        return BitcoinUtils.reverseBytes32(hash);
    }

    /**
     * @dev Get blocj header struct for a given block hash
     * @param blockHash bytes32 Block hash in reverse byte order
     * @return BitcoinUtils.BlockHeader Block header struct
     */
    function getHeader(bytes32 blockHash) external view returns (BitcoinUtils.BlockHeader memory) {
        return headers[blockHash];
    }

    /**
     * @dev Get the latest block hash
     * @return bytes32 Latest block hash
     */
    function getLatestHeaderHash() external view returns (bytes32) {
        return latestCheckpointHeaderHash;
    }

    /**
     * @dev Get the latest block header
     * @return BitcoinUtils.BlockHeader Latest block header
     */
    function getLatestCheckpoint() external view returns (BitcoinUtils.BlockHeader memory) {
        return headers[latestCheckpointHeaderHash];
    }

    /**
     * @notice Generate merkle proof for a transaction using binary index path
     * @dev Index is provided as uint but represents binary path in the tree
     *      The maximum value of the index is checked against array length
     * @param transactions Array of transaction hashes in reverse byte in tree order
     * @param index Binary path index to the target transaction
     * @return proof Array of proof hashes inn natural byte order
     * @return directions Array of boolean values indicating left (false) or right (true) placements
     */
    function generateMerkleProof(bytes32[] memory transactions, uint256 index)
        public
        view
        returns (bytes32[] memory proof, bool[] memory directions)
    {
        require(index < transactions.length, INVALID_TRANSACTION_INDEX());
        return BitcoinUtils.generateMerkleProof(transactions, index);
    }

    /**
     * @notice Verify if a transaction is included in a block using a Merkle proof
     * @dev All inputs should be in Bitcoin's display format (reversed byte order)
     * @param txId Transaction ID to verify (in Bitcoin's reversed byte order)
     * @param merkleRoot Expected Merkle root (in Bitcoin's reversed byte order)
     * @param proof Array of proof hashes (in Bitcoin's reversed byte order)
     * @param index Index of the transaction in the block (0-based)
     * @return bool True if the proof is valid
     */
    function verifyTxInclusion(bytes32 txId, bytes32 merkleRoot, bytes32[] calldata proof, uint256 index)
        external
        view
        returns (bool)
    {
        return BitcoinUtils.verifyTxInclusion(txId, merkleRoot, proof, index);
    }

    /**
     * @dev Calculate merkle root in reversed byte order
     * @param transactions Array of transaction hashes in reverse byte in tree order
     * @return bytes32 merkle root
     */
    function calculateMerkleRoot(bytes32[] calldata transactions) external view returns (bytes32) {
        bytes32[] memory txIdsInNaturalBytesOrder = BitcoinUtils.reverseBytes32Array(transactions);
        // First get the double SHA256 hash
        bytes32 hash = BitcoinUtils.calculateMerkleRootInNaturalByteOrder(txIdsInNaturalBytesOrder);

        // Then reverse it
        return BitcoinUtils.reverseBytes32(hash);
    }
}
