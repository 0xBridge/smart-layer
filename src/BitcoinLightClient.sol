// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {UUPSUpgradeable} from "@openzeppelin-upgrades/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {BitcoinTxnParser} from "./libraries/BitcoinTxnParser.sol";
import {BitcoinUtils} from "./libraries/BitcoinUtils.sol";

/**
 * @title BitcoinLightClient
 * @notice A lightweight client for Bitcoin blockchain header validation and transaction verification
 * @dev Implements SPV (Simple Payment Verification) for Bitcoin transactions
 */
contract BitcoinLightClient is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    // Error codes
    error INVALID_HEADER_LENGTH();
    error INVALID_PROOF_OF_WORK();
    error INVALID_HEADER_CHAIN();
    error CHAIN_NOT_CONNECTED();
    error INVALID_TRANSACTION_INDEX();
    error BLOCK_NOT_FOUND();

    // Roles
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Length of a Bitcoin block header
    uint8 internal constant HEADER_LENGTH = 80;

    // State variables (Ensure the storage layout is maintained)
    bytes32 internal _latestCheckpointHeaderHash;
    mapping(bytes32 => BitcoinUtils.BlockHeader) internal _headers;

    // Events
    event BlockHeaderSubmitted(bytes32 indexed blockHash, bytes32 indexed prevBlock, uint32 height);
    event ContractUpgraded(address indexed implementation);

    /**
     * @notice Constructor that initializes the contract
     * @dev This disables initializers to prevent calling initialize() more than once
     */
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
     * @dev Can only be called once due to initializer modifier
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

        _latestCheckpointHeaderHash = BitcoinUtils.getBlockHashFromParams(header);
        _headers[_latestCheckpointHeaderHash] = header;
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
     * @param intermediateHeaders Array of intermediate headers (in reverse array order)
     * @return blockHash The hash of the submitted block
     * @dev Only accounts with appropriate role can submit headers
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
    ) external returns (bytes32 blockHash) {
        BitcoinUtils.BlockHeader memory header = BitcoinUtils.BlockHeader({
            version: blockVersion,
            timestamp: blockTimestamp,
            difficultyBits: difficultyBits,
            nonce: nonce,
            height: height,
            prevBlock: prevBlock,
            merkleRoot: merkleRoot
        });
        blockHash = BitcoinUtils.getBlockHashFromParams(header);
        _submitBlockHeader(blockHash, header, intermediateHeaders);
    }

    /**
     * @notice Submit a new raw block header along with intermediate headers
     * @param rawHeader Raw block header bytes
     * @param intermediateHeaders Array of intermediate headers (in reverse array order)
     * @return blockHash The hash of the submitted block
     * @dev Only accounts with appropriate role can submit headers
     */
    function submitRawBlockHeader(bytes calldata rawHeader, bytes[] calldata intermediateHeaders)
        external
        returns (bytes32 blockHash)
    {
        blockHash = getBlockHash(rawHeader);
        BitcoinUtils.BlockHeader memory header = BitcoinUtils.parseBlockHeader(rawHeader);
        _submitBlockHeader(blockHash, header, intermediateHeaders);
    }

    /**
     * @notice Internal function to submit block header
     * @param blockHash Block hash
     * @param header Block header
     * @param intermediateHeaders Array of intermediate headers
     * @dev Validates proof of work and chain connection
     */
    function _submitBlockHeader(
        bytes32 blockHash,
        BitcoinUtils.BlockHeader memory header,
        bytes[] calldata intermediateHeaders
    ) internal {
        if (!BitcoinUtils.verifyProofOfWork(blockHash, header.difficultyBits)) {
            revert INVALID_PROOF_OF_WORK();
        }

        if (intermediateHeaders.length > 0) {
            bool isValid = verifyHeaderChain(header.prevBlock, intermediateHeaders);
            if (!isValid) revert INVALID_HEADER_CHAIN();
        } else {
            if (header.prevBlock != _latestCheckpointHeaderHash) revert CHAIN_NOT_CONNECTED();
        }

        uint32 latestHeaderHeight = _headers[_latestCheckpointHeaderHash].height;
        header.height = latestHeaderHeight + uint32(intermediateHeaders.length) + 1;
        _latestCheckpointHeaderHash = blockHash;
        _headers[_latestCheckpointHeaderHash] = header;

        emit BlockHeaderSubmitted(blockHash, header.prevBlock, header.height);
    }

    /**
     * @notice Verify a chain of headers connects properly
     * @param currentPrevHash Previous hash of the latest header
     * @param intermediateHeaders Array of intermediate headers
     * @return True if the header chain is valid and connects to the latest checkpoint
     * @dev Verifies proof of work and proper chaining of all intermediate headers
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

        return currentPrevHash == _latestCheckpointHeaderHash;
    }

    /**
     * @notice Get block hash from header
     * @param blockHeader Raw block header bytes
     * @return Block hash in reverse byte order
     * @dev Computes double SHA256 hash of the header
     */
    function getBlockHash(bytes memory blockHeader) public view returns (bytes32) {
        if (blockHeader.length != HEADER_LENGTH) revert INVALID_HEADER_LENGTH();
        bytes32 hash = BitcoinUtils.sha256DoubleHash(blockHeader);
        return BitcoinUtils.reverseBytes32(hash);
    }

    /**
     * @notice Get block header for a given block hash
     * @param blockHash Block hash in reverse byte order
     * @return The block header data structure
     */
    function getHeader(bytes32 blockHash) external view returns (BitcoinUtils.BlockHeader memory) {
        return _headers[blockHash];
    }

    /**
     * @notice Get the latest block hash
     * @return The latest checkpoint block hash
     */
    function getLatestHeaderHash() external view returns (bytes32) {
        return _latestCheckpointHeaderHash;
    }

    /**
     * @notice Get the latest block header
     * @return The latest checkpoint block header
     */
    function getLatestCheckpoint() external view returns (BitcoinUtils.BlockHeader memory) {
        return _headers[_latestCheckpointHeaderHash];
    }

    /**
     * @notice Get the merkle root for a block
     * @param blockHash Block hash to get the merkle root for
     * @return The merkle root of the specified block
     * @dev Reverts if block not found (commented out for testing)
     */
    function getMerkleRootForBlock(bytes32 blockHash) external view returns (bytes32) {
        if (_headers[blockHash].height == 0) revert BLOCK_NOT_FOUND();
        return _headers[blockHash].merkleRoot;
    }

    /**
     * @notice Generate merkle proof for a transaction
     * @param transactions Array of transaction hashes
     * @param index Binary path index
     * @return proof Array of proof hashes
     * @return directions Array of boolean values indicating left (false) or right (true) placements
     * @dev Reverts if index is invalid
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
     * @return True if the transaction is included in the block
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
     * @return Calculated merkle root in Bitcoin's display format
     */
    function calculateMerkleRoot(bytes32[] calldata transactions) external view returns (bytes32) {
        bytes32[] memory txIdsInNaturalBytesOrder = BitcoinUtils.reverseBytes32Array(transactions);
        bytes32 hash = BitcoinUtils.calculateMerkleRootInNaturalByteOrder(txIdsInNaturalBytesOrder);
        return BitcoinUtils.reverseBytes32(hash);
    }

    /**
     * @notice Authorization function for UUPS proxy upgrade
     * @param newImplementation Address of the new implementation contract
     * @dev Only accounts with UPGRADER_ROLE can upgrade the contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        emit ContractUpgraded(newImplementation);
    }

    /**
     * @notice Returns the version number for this contract implementation
     * @return String representing the version number
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @notice Extracts OP_RETURN data from a raw Bitcoin transaction
     * @param rawTxnHex The raw Bitcoin transaction bytes
     * @return metadata Structured metadata containing receiver address, locked Amount, chain ID, and base token amount
     */
    function decodeTransactionMetadata(bytes calldata rawTxnHex)
        public
        pure
        returns (BitcoinTxnParser.TransactionMetadata memory metadata)
    {
        // Parse transaction outputs
        bytes memory opReturnData = BitcoinTxnParser.decodeBitcoinTxn(rawTxnHex);
        // Decode metadata from OP_RETURN data
        return BitcoinTxnParser.decodeMetadata(opReturnData);
    }

    /**
     * @notice Submit a historical block header
     * @param blockVersion Block version
     * @param blockTimestamp Block timestamp
     * @param difficultyBits Block difficulty bits
     * @param nonce Block nonce
     * @param height Block height
     * @param prevBlock Previous block hash
     * @param merkleRoot Block merkle root
     * @param intermediateHeaders Array of intermediate headers (in chronological order from latest checkpoint)
     * @return blockHash The hash of the submitted block
     */
    function submitHistoricalBlockHeader(
        uint32 blockVersion,
        uint32 blockTimestamp,
        uint32 difficultyBits,
        uint32 nonce,
        uint32 height,
        bytes32 prevBlock,
        bytes32 merkleRoot,
        bytes[] calldata intermediateHeaders
    ) external returns (bytes32 blockHash) {
        BitcoinUtils.BlockHeader memory header = BitcoinUtils.BlockHeader({
            version: blockVersion,
            timestamp: blockTimestamp,
            difficultyBits: difficultyBits,
            nonce: nonce,
            height: height,
            prevBlock: prevBlock,
            merkleRoot: merkleRoot
        });
        blockHash = BitcoinUtils.getBlockHashFromParams(header);
        _submitHistoricalBlockHeader(blockHash, header, intermediateHeaders);
    }

    /**
     * @notice Internal function to submit historical block header
     * @param blockHash Block hash
     * @param header Block header
     * @param intermediateHeaders Array of intermediate headers (in chronological order from latest checkpoint)
     * @dev Validates proof of work and chain connection from latest checkpoint down to historical header
     */
    function _submitHistoricalBlockHeader(
        bytes32 blockHash,
        BitcoinUtils.BlockHeader memory header,
        bytes[] calldata intermediateHeaders
    ) internal {
        if (!BitcoinUtils.verifyProofOfWork(blockHash, header.difficultyBits)) {
            revert INVALID_PROOF_OF_WORK();
        }

        // For historical headers, we need to verify the chain connection from latest checkpoint down
        if (intermediateHeaders.length > 0) {
            bool isValid = verifyHistoricalHeaderChain(header, intermediateHeaders);
            if (!isValid) revert INVALID_HEADER_CHAIN();
        } else {
            // If no intermediate headers, check if this header connects to an existing header
            if (_headers[header.prevBlock].height == 0) revert CHAIN_NOT_CONNECTED();
        }

        // Store the header
        _headers[blockHash] = header;

        emit BlockHeaderSubmitted(blockHash, header.prevBlock, header.height);
    }

    /**
     * @notice Verify a chain of headers from latest checkpoint down to historical header
     * @param historicalHeader The historical header being submitted
     * @param intermediateHeaders Array of intermediate headers in chronological order from latest checkpoint
     * @return True if the header chain is valid and connects from latest checkpoint to historical header
     */
    function verifyHistoricalHeaderChain(
        BitcoinUtils.BlockHeader memory historicalHeader,
        bytes[] calldata intermediateHeaders
    ) public view returns (bool) {
        bytes32 currentHash = _latestCheckpointHeaderHash;
        BitcoinUtils.BlockHeader memory currentHeader = _headers[currentHash];

        // Verify headers in chronological order from latest checkpoint down
        for (uint256 i = 0; i < intermediateHeaders.length; i++) {
            BitcoinUtils.BlockHeader memory intermediateHeader = BitcoinUtils.parseBlockHeader(intermediateHeaders[i]);

            // Verify the current header points to the intermediate header
            if (currentHeader.prevBlock != BitcoinUtils.getBlockHashFromParams(intermediateHeader)) {
                return false;
            }

            // Verify proof of work for intermediate header
            bytes32 intermediateHash = BitcoinUtils.getBlockHashFromParams(intermediateHeader);
            if (!BitcoinUtils.verifyProofOfWork(intermediateHash, intermediateHeader.difficultyBits)) {
                return false;
            }

            // Move to next header
            currentHash = intermediateHash;
            currentHeader = intermediateHeader;
        }

        // Finally verify connection to the historical header
        return currentHeader.prevBlock == BitcoinUtils.getBlockHashFromParams(historicalHeader);
    }
}
