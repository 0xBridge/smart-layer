// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BitcoinUtils} from "./libs/BitcoinUtils.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgrades/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

contract BitcoinLightClient is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    // Error codes
    error INVALID_HEADER_LENGTH();
    error INVALID_PROOF_OF_WORK();
    error INVALID_HEADER_CHAIN();
    error CHAIN_NOT_CONNECTED();
    error INVALID_TRANSACTION_INDEX();

    // Roles
    bytes32 private constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Length of a Bitcoin block header
    uint8 private constant HEADER_LENGTH = 80;

    // State variables (Ensure the storage layout is maintained)
    bytes32 private latestCheckpointHeaderHash;
    mapping(bytes32 => BitcoinUtils.BlockHeader) private headers;

    // Events
    event BlockHeaderSubmitted(bytes32 indexed blockHash, bytes32 indexed prevBlock, uint32 height);
    event ContractUpgraded(address indexed implementation);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor)
     * @param admin Address that will have admin role
     * @param blockVersion Initial block version
     * @param blockTimestamp Initial block timestamp
     * @param difficultyBits Initial block difficulty bits
     * @param nonce Initial block nonce
     * @param height Initial block height
     * @param prevBlock Initial previous block hash
     * @param merkleRoot Initial merkle root
     */
    function initialize(
        address admin,
        uint32 blockVersion,
        uint32 blockTimestamp,
        uint32 difficultyBits,
        uint32 nonce,
        uint32 height,
        bytes32 prevBlock,
        bytes32 merkleRoot
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        // Initialize first checkpoint
        BitcoinUtils.BlockHeader memory header = BitcoinUtils.BlockHeader({
            version: blockVersion,
            timestamp: blockTimestamp,
            difficultyBits: difficultyBits,
            nonce: nonce,
            height: height,
            prevBlock: prevBlock,
            merkleRoot: merkleRoot
        });

        latestCheckpointHeaderHash = BitcoinUtils.getBlockHashFromParams(header);
        headers[latestCheckpointHeaderHash] = header;
    }

    /**
     * @notice Submit a new block header fields along with intermediate headers
     * @param blockVersion Block version
     * @param blockTimestamp Block timestamp
     * @param difficultyBits Block difficulty bits
     * @param nonce Block nonce
     * @param height Block height
     * @param prevBlock Previous block hash
     * @param merkleRoot Block merkle root
     * @param intermediateHeaders Array of intermediate headers
     * @dev Only accounts with BLOCK_SUBMIT_ROLE can submit headers
     */
    function submitBlockHeader(
        uint32 blockVersion,
        uint32 blockTimestamp,
        uint32 difficultyBits,
        uint32 nonce,
        uint32 height,
        bytes32 prevBlock,
        bytes32 merkleRoot,
        bytes[] calldata intermediateHeaders
    ) external returns (bool) {
        BitcoinUtils.BlockHeader memory header = BitcoinUtils.BlockHeader({
            version: blockVersion,
            timestamp: blockTimestamp,
            difficultyBits: difficultyBits,
            nonce: nonce,
            height: height,
            prevBlock: prevBlock,
            merkleRoot: merkleRoot
        });
        bytes32 blockHash = BitcoinUtils.getBlockHashFromParams(header);
        return _submitBlockHeader(blockHash, header, intermediateHeaders);
    }

    /**
     * @notice Submit a new raw block header along with intermediate headers
     * @param rawHeader Raw block header bytes
     * @param intermediateHeaders Array of intermediate headers
     * @dev Only accounts with BLOCK_SUBMIT_ROLE can submit headers
     */
    function submitRawBlockHeader(bytes calldata rawHeader, bytes[] calldata intermediateHeaders)
        external
        returns (bool)
    {
        bytes32 blockHash = getBlockHash(rawHeader);
        BitcoinUtils.BlockHeader memory header = BitcoinUtils.parseBlockHeader(rawHeader);
        return _submitBlockHeader(blockHash, header, intermediateHeaders);
    }

    /**
     * @notice Internal function to submit block header
     * @param blockHash Block hash
     * @param header Block header
     * @param intermediateHeaders Array of intermediate headers
     */
    function _submitBlockHeader(
        bytes32 blockHash,
        BitcoinUtils.BlockHeader memory header,
        bytes[] calldata intermediateHeaders
    ) internal returns (bool) {
        if (!BitcoinUtils.verifyProofOfWork(blockHash, header.difficultyBits)) {
            revert INVALID_PROOF_OF_WORK();
        }

        if (intermediateHeaders.length > 0) {
            bool isValid = verifyHeaderChain(header.prevBlock, intermediateHeaders);
            if (!isValid) revert INVALID_HEADER_CHAIN();
        } else {
            if (header.prevBlock != latestCheckpointHeaderHash) revert CHAIN_NOT_CONNECTED();
        }

        uint32 latestHeaderHeight = headers[latestCheckpointHeaderHash].height;
        header.height = latestHeaderHeight + uint32(intermediateHeaders.length) + 1;
        latestCheckpointHeaderHash = blockHash;
        headers[latestCheckpointHeaderHash] = header;

        emit BlockHeaderSubmitted(blockHash, header.prevBlock, header.height);
        return true;
    }

    /**
     * @notice Verify a chain of headers connects properly
     * @param currentPrevHash Previous hash of the latest header
     * @param intermediateHeaders Array of intermediate headers
     */
    function verifyHeaderChain(bytes32 currentPrevHash, bytes[] calldata intermediateHeaders)
        public
        view
        returns (bool)
    {
        for (uint256 i = 0; i < intermediateHeaders.length; i++) {
            BitcoinUtils.BlockHeader memory intermediateHeader = BitcoinUtils.parseBlockHeader(intermediateHeaders[i]);

            bytes32 intermediateHash = BitcoinUtils.sha256DoubleHash(intermediateHeaders[i]);
            intermediateHash = BitcoinUtils.reverseBytes32(intermediateHash);

            if (currentPrevHash != intermediateHash) revert INVALID_HEADER_CHAIN();

            if (!BitcoinUtils.verifyProofOfWork(intermediateHash, intermediateHeader.difficultyBits)) {
                revert INVALID_PROOF_OF_WORK();
            }

            currentPrevHash = intermediateHeader.prevBlock;
        }

        return currentPrevHash == latestCheckpointHeaderHash;
    }

    /**
     * @notice Get block hash from header
     * @param blockHeader Raw block header bytes
     * @return Block hash in reverse byte order
     */
    function getBlockHash(bytes memory blockHeader) public view returns (bytes32) {
        if (blockHeader.length != HEADER_LENGTH) revert INVALID_HEADER_LENGTH();
        bytes32 hash = BitcoinUtils.sha256DoubleHash(blockHeader);
        return BitcoinUtils.reverseBytes32(hash);
    }

    /**
     * @notice Get block header for a given block hash
     * @param blockHash Block hash in reverse byte order
     */
    function getHeader(bytes32 blockHash) external view returns (BitcoinUtils.BlockHeader memory) {
        return headers[blockHash];
    }

    /**
     * @notice Get the latest block hash
     */
    function getLatestHeaderHash() external view returns (bytes32) {
        return latestCheckpointHeaderHash;
    }

    /**
     * @notice Get the latest block header
     */
    function getLatestCheckpoint() external view returns (BitcoinUtils.BlockHeader memory) {
        return headers[latestCheckpointHeaderHash];
    }

    /**
     * @notice Generate merkle proof for a transaction
     * @param transactions Array of transaction hashes
     * @param index Binary path index
     */
    function generateMerkleProof(bytes32[] memory transactions, uint256 index)
        public
        view
        returns (bytes32[] memory proof, bool[] memory directions)
    {
        if (index >= transactions.length) revert INVALID_TRANSACTION_INDEX();
        return BitcoinUtils.generateMerkleProof(transactions, index);
    }

    /**
     * @notice Verify transaction inclusion using Merkle proof
     * @param txId Transaction ID
     * @param merkleRoot Merkle root
     * @param proof Proof hashes
     * @param index Transaction index
     */
    function verifyTxInclusion(bytes32 txId, bytes32 merkleRoot, bytes32[] calldata proof, uint256 index)
        external
        view
        returns (bool)
    {
        return BitcoinUtils.verifyTxInclusion(txId, merkleRoot, proof, index);
    }

    /**
     * @notice Calculate merkle root
     * @param transactions Array of transaction hashes
     */
    function calculateMerkleRoot(bytes32[] calldata transactions) external view returns (bytes32) {
        bytes32[] memory txIdsInNaturalBytesOrder = BitcoinUtils.reverseBytes32Array(transactions);
        bytes32 hash = BitcoinUtils.calculateMerkleRootInNaturalByteOrder(txIdsInNaturalBytesOrder);
        return BitcoinUtils.reverseBytes32(hash);
    }

    /**
     * @dev Required override for UUPS proxy upgrade authorization
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        emit ContractUpgraded(newImplementation);
    }

    /**
     * @dev Version number for this contract implementation
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
