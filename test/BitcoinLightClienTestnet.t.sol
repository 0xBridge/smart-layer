// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {BitcoinUtils} from "../src/libraries/BitcoinUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BitcoinTxnParser} from "../src/libraries/BitcoinTxnParser.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// const _options = Options.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, MSG_VALUE);

contract BitcoinLightClientTest is Test {
    BitcoinLightClient public bitcoinLightClient;
    BitcoinLightClient public client;
    address public constant SUBMITTER = address(0x1234);
    address public constant ADMIN = address(0x5678);

    // Block 10 data (real Bitcoin block after initial)
    bytes constant BLOCK_10_HEADER =
        hex"010000000508085c47cc849eb80ea905cc7800a3be674ffc57263cf210c59d8d00000000112ba175a1e04b14ba9e7ea5f76ab640affeef5ec98173ac9799a852fa39add320cd6649ffff001d1e2de565";
    bytes32 constant BLOCK_10_HASH = 0x000000002c05cc2e78923c34df87fd108b22221ac6076c18f3ade378a4d915e9;

    // Block 11 data (real Bitcoin block after initial)
    bytes constant BLOCK_11_HEADER =
        hex"01000000e915d9a478e3adf3186c07c61a22228b10fd87df343c92782ecc052c000000006e06373c80de397406dc3d19c90d71d230058d28293614ea58d6a57f8f5d32f8b8ce6649ffff001d173807f8";
    bytes32 constant BLOCK_11_HASH = 0x0000000097be56d606cdd9c54b04d4747e957d3608abe69198c661f2add73073;

    // Block 12 data (real Bitcoin block after initial)
    bytes constant BLOCK_12_HEADER =
        hex"010000007330d7adf261c69891e6ab08367d957e74d4044bc5d9cd06d656be9700000000b8c8754fabb0ffeb04ca263a1368c39c059ca0d4af3151b876f27e197ebb963bc8d06649ffff001d3f596a0c";
    bytes32 constant BLOCK_12_HASH = 0x0000000027c2488e2510d1acf4369787784fa20ee084c258b58d9fbd43802b5e;

    // Block 12 data (real Bitcoin block after initial)
    bytes constant BLOCK_109_HEADER =
        hex"01000000cf247ab093cae5a6698f9f3fa5e9bd885ef6589f2e5e5cdd9dd6af420000000030b2b4faab68a1669e4eda67442919f25561f8df26237de4760425433f7f00a33ec26949ffff001d359e2d4e";
    bytes32 constant BLOCK_109_HASH = 0x000000003f5dccc4e0bdac7081755b9d9ee17e7737316202b900d1c567c5abae;

    function setUp() public {
        BitcoinUtils.BlockHeader memory initialHeader = _getInitialHeader();
        // Deploy with correct constructor parameters
        vm.startPrank(SUBMITTER);

        // Deploy implementation
        bitcoinLightClient = new BitcoinLightClient();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            BitcoinLightClient.initialize.selector,
            ADMIN,
            initialHeader.version,
            initialHeader.timestamp,
            initialHeader.difficultyBits,
            initialHeader.nonce,
            initialHeader.height,
            initialHeader.prevBlock,
            initialHeader.merkleRoot
        );

        ERC1967Proxy proxyContract = new ERC1967Proxy(address(bitcoinLightClient), initData);

        client = BitcoinLightClient(address(proxyContract));
        vm.stopPrank();
    }

    function _getInitialHeader() private pure returns (BitcoinUtils.BlockHeader memory) {
        return BitcoinUtils.BlockHeader(
            1,
            1231473952,
            486604799,
            1709518110,
            10,
            0x000000008d9dc510f23c2657fc4f67bea30078cc05a90eb89e84cc475c080805,
            0xd3ad39fa52a89997ac7381c95eeffeaf40b66af7a57e9eba144be0a175a12b11
        );
    }

    function testInitialState() public view {
        assertEq(client.getLatestHeaderHash(), BLOCK_10_HASH);

        BitcoinUtils.BlockHeader memory checkpoint = client.getHeader(BLOCK_10_HASH);
        assertEq(checkpoint.height, 10);
        assertEq(checkpoint.version, 1);
        assertEq(checkpoint.timestamp, 1231473952);
        assertEq(checkpoint.difficultyBits, 486604799);
        assertEq(checkpoint.nonce, 1709518110);
    }

    function testSubmitNextBlock() public {
        vm.startPrank(SUBMITTER);

        // Submit block 11 (direct connection to initial)
        client.submitRawBlockHeader(BLOCK_11_HEADER, new bytes[](0));

        assertEq(client.getLatestHeaderHash(), BLOCK_11_HASH);

        BitcoinUtils.BlockHeader memory checkpoint = client.getLatestCheckpoint();
        assertEq(checkpoint.height, 11);
        vm.stopPrank();
    }

    function testFailInvalidPoW() public {
        vm.startPrank(SUBMITTER);

        // Modify nonce to make PoW invalid
        bytes memory invalidHeader = BLOCK_11_HEADER;
        // Modify the last 4 bytes (nonce)
        assembly {
            mstore8(add(invalidHeader, 79), 0x00)
            mstore8(add(invalidHeader, 78), 0x00)
            mstore8(add(invalidHeader, 77), 0x00)
            mstore8(add(invalidHeader, 76), 0x00)
        }

        client.submitRawBlockHeader(invalidHeader, new bytes[](0));
        vm.stopPrank();
    }

    function testFailInvalidChain() public {
        vm.startPrank(SUBMITTER);

        // Try to submit block 12 directly without block 11
        client.submitRawBlockHeader(BLOCK_12_HEADER, new bytes[](0));
        vm.stopPrank();
    }

    function testFailInvalidIntermediateHeader() public {
        vm.startPrank(SUBMITTER);

        // Create invalid intermediate headers array
        bytes[] memory invalidIntermediateHeaders = new bytes[](1);
        invalidIntermediateHeaders[0] = BLOCK_12_HEADER; // Wrong order

        client.submitRawBlockHeader(BLOCK_11_HEADER, invalidIntermediateHeaders);
        vm.stopPrank();
    }

    // Add test for submitting invalid header length
    function testFailInvalidHeaderLength() public {
        vm.startPrank(SUBMITTER);
        bytes memory invalidHeader = hex"0011"; // Too short
        client.submitRawBlockHeader(invalidHeader, new bytes[](0));
        vm.stopPrank();
    }

    // Add test for checking block height increments
    function testSubmitWithIntermediateBlock() public {
        vm.startPrank(SUBMITTER);

        // Submit block 12
        bytes[] memory intermediateHeaders = new bytes[](1);
        intermediateHeaders[0] = BLOCK_11_HEADER;
        client.submitRawBlockHeader(BLOCK_12_HEADER, intermediateHeaders);

        BitcoinUtils.BlockHeader memory checkpoint2 = client.getLatestCheckpoint();
        assertEq(checkpoint2.height, 12);
        vm.stopPrank();
    }

    // Add test for 98 intermediate headers for the next block submission
    function testBlockchainContinuity() public {
        vm.startPrank(SUBMITTER);

        bytes[] memory intermediateHeaders = new bytes[](3);
        // This is BLOCK_108_HEADER and intermediate headers[1] is BLOCK_107_HEADER, intermediate headers[2] is BLOCK_106_HEADER, ... (reverse order)

        client.submitRawBlockHeader(BLOCK_109_HEADER, intermediateHeaders);

        BitcoinUtils.BlockHeader memory checkpoint = client.getLatestCheckpoint();
        assertEq(checkpoint.height, 109);
        vm.stopPrank();
    }

    // Add test for transaction inclusion
    function testVerifyTxInclusion() public view {
        // Using real Bitcoin block #100000 data
        // https://btcscan.org/block/000000000003ba27aa200b1cecaad478d2b00432346c3f1f3986da1afd33e506
        bytes32[] memory txids = new bytes32[](4);
        txids[0] = 0x8c14f0db3df150123e6f3dbbf30f8b955a8249b62ac1d1ff16284aefa3d06d87;
        txids[1] = 0xfff2525b8931402dd09222c50775608f75787bd2b87e56995a7bdd30f79702c4;
        txids[2] = 0x6359f0868171b1d194cbee1af2f16ea598ae8fad666d9b012c8ed2b79a236ec4;
        txids[3] = 0xe9a66845e05d5abc0ad04ec80f774a7e585c6e8db975962d069a522137b80c1d;
        bytes32 merkleRoot = client.calculateMerkleRoot(txids);

        // Test Case 1: Valid inclusion for first transaction
        {
            // Generate proof for the first transaction (index 0)
            uint256 index = 1;
            (bytes32[] memory proof,) = client.generateMerkleProof(txids, index);

            // Verify the transaction is included
            bool isIncluded = client.verifyTxInclusion(txids[index], merkleRoot, proof, index);
            assertTrue(isIncluded, "Transaction should be included in the merkle tree");
        }

        // Test Case 2: Invalid inclusion (wrong transaction ID)
        {
            // Generate proof for the first transaction (index 0)
            uint256 index = 0;
            (bytes32[] memory proof,) = client.generateMerkleProof(txids, index);

            // Try to verify with a different transaction ID
            bytes32 wrongTxId = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
            bool isIncluded = client.verifyTxInclusion(wrongTxId, merkleRoot, proof, index);
            assertFalse(isIncluded, "Transaction should not be included in the merkle tree");
        }

        // Test Case 3: Invalid order for incorrect transaction inclusion
        {
            // Generate proof for the first transaction (index 0)
            uint256 index = 1;
            (bytes32[] memory proof,) = client.generateMerkleProof(txids, index);

            // Verify the transaction is included
            bool isIncluded = client.verifyTxInclusion(txids[3], merkleRoot, proof, index);
            assertFalse(isIncluded, "Incorrect transaction order in the merkle tree");
        }
    }

    // Another test case to verify the inclusion of a transaction in a block
    function testVerifyTxInclusionWithMoreTxns() public view {
        // Using real Bitcoin block #100001 data
        // https://btcscan.org/block/00000000000080b66c911bd5ba14a74260057311eaeb1982802f7010f1a9f090
        bytes32[] memory txids = new bytes32[](12);
        txids[0] = 0xbb28a1a5b3a02e7657a81c38355d56c6f05e80b9219432e3352ddcfc3cb6304c;
        txids[1] = 0xfbde5d03b027d2b9ba4cf5d4fecab9a99864df2637b25ea4cbcb1796ff6550ca;
        txids[2] = 0x8131ffb0a2c945ecaf9b9063e59558784f9c3a74741ce6ae2a18d0571dac15bb;
        txids[3] = 0xd6c7cb254aa7a5fd446e8b48c307890a2d4e426da8ad2e1191cc1d8bbe0677d7;
        txids[4] = 0xce29e5407f5e4c9ad581c337a639f3041b24220d5aa60370d96a39335538810b;
        txids[5] = 0x45a38677e1be28bd38b51bc1a1c0280055375cdf54472e04c590a989ead82515;
        txids[6] = 0xc5abc61566dbb1c4bce5e1fda7b66bed22eb2130cea4b721690bc1488465abc9;
        txids[7] = 0xa71f74ab78b564004fffedb2357fb4059ddfc629cb29ceeb449fafbf272104ca;
        txids[8] = 0xfda204502a3345e08afd6af27377c052e77f1fefeaeb31bdd45f1e1237ca5470;
        txids[9] = 0xd3cd1ee6655097146bdae1c177eb251de92aed9045a0959edc6b91d7d8c1f158;
        txids[10] = 0xcb00f8a0573b18faa8c4f467b049f5d202bf1101d9ef2633bc611be70376a4b4;
        txids[11] = 0x05d07bb2de2bda1115409f99bf6b626d23ecb6bed810d8be263352988e4548cb;

        bytes32 merkleRoot = client.calculateMerkleRoot(txids);

        // Test Case 1: Valid inclusion for first transaction
        {
            // Generate proof for the first transaction (index 0)
            uint256 index = 1;
            (bytes32[] memory proof,) = client.generateMerkleProof(txids, index);

            // Verify the transaction is included
            bool isIncluded = client.verifyTxInclusion(txids[index], merkleRoot, proof, index);
            assertTrue(isIncluded, "Transaction should be included in the merkle tree");
        }

        // Test Case 2: Invalid inclusion (wrong transaction ID)
        {
            // Generate proof for the first transaction (index 0)
            uint256 index = 0;
            (bytes32[] memory proof,) = client.generateMerkleProof(txids, index);

            // Try to verify with a different transaction ID
            bytes32 wrongTxId = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
            bool isIncluded = client.verifyTxInclusion(wrongTxId, merkleRoot, proof, index);
            assertFalse(isIncluded, "Transaction should not be included in the merkle tree");
        }

        // Test Case 3: Invalid order for incorrect transaction inclusion
        {
            // Generate proof for the first transaction (index 0)
            uint256 index = 1;
            (bytes32[] memory proof,) = client.generateMerkleProof(txids, index);

            // Verify the transaction is included
            bool isIncluded = client.verifyTxInclusion(txids[3], merkleRoot, proof, index);
            assertFalse(isIncluded, "Incorrect transaction order in the merkle tree");
        }
    }

    // Add test for valid OP_RETURN data
    function testDecodeTransactionMetadata() public view {
        bytes memory validTxnHex =
            hex"0200000000010198125705e23e351caccd7435b4d41ee3b685b460b7121be3b0f5089dd507a7b50300000000ffffffff04e803000000000000225120c35241ec07fba00f5ea6e81b63f5af8087dc5e329a01d4ef9d8d6b498abcd902881300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a30001441588441c41d5528cc6afa3a2a732afeca9e9452000800000000000003e80004000000050008000000000001869fd72f000000000000160014d6a279dc882b830c5562b49e3e25bf3c5767ab73024730440220398d6577bc7adbe65b23e7ca7819d5bd28ed5b919108a89d3f607ddf8b78ca0e02204085b4547b7555dcf3be79e64ece0dfdc469a21c301bf05c4c36a616b1346f7901210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb00000000"; // Replace with a valid raw Bitcoin transaction hex
        BitcoinTxnParser.TransactionMetadata memory metadata = client.decodeTransactionMetadata(validTxnHex);

        address expectedReceiverAddress = 0x41588441C41D5528CC6AFa3a2a732afeca9e9452;
        uint256 expectedAmount = 1000;
        uint256 expectedChainId = 5;
        uint256 expectedNativeTokenAmount = 99999;

        // Add assertions to check the expected values in metadata
        assertEq(metadata.receiverAddress, expectedReceiverAddress);
        assertEq(metadata.lockedAmount, expectedAmount);
        assertEq(metadata.chainId, expectedChainId);
        assertEq(metadata.nativeTokenAmount, expectedNativeTokenAmount);
    }

    // Add test for valid OP_RETURN data
    function testDecodeAnotherTransactionMetadata() public view {
        bytes memory validTxnHex =
            hex"02000000000101f1cfa7732fddc29a1e0fd6fa3b285d651664da483b00ba636a4aaf47e8a3ec210000000000ffffffff04e80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa1d00700000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a30001403aa93e006fba956cdbafa2b8ef789d0cb63e7b40008000000000000271000040000007b00080000000000004e202e2e000000000000160014d6a279dc882b830c5562b49e3e25bf3c5767ab7302483045022100a6bbe0b8073066cfb3f0b98d7e51b47d030b34745289964efe8835a60e7bdf8602207e9182068f37cff1d8e6ed8f7463c15718544c30e14e8278fd874a14222d7c6901210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb00000000"; // Replace with a valid raw Bitcoin transaction hex
        BitcoinTxnParser.TransactionMetadata memory metadata = client.decodeTransactionMetadata(validTxnHex);

        address expectedReceiverAddress = 0x03AA93e006fBa956cdBAfa2b8EF789D0Cb63e7b4;
        uint256 expectedAmount = 10000;
        uint256 expectedChainId = 123;
        uint256 expectedNativeTokenAmount = 20000;

        // Add assertions to check the expected values in metadata
        assertEq(metadata.receiverAddress, expectedReceiverAddress);
        assertEq(metadata.lockedAmount, expectedAmount);
        assertEq(metadata.chainId, expectedChainId);
        assertEq(metadata.nativeTokenAmount, expectedNativeTokenAmount);
    }

    // Add test for transaction with no OP_RETURN data
    function testFailDecodeTransactionMetadataNoOpReturn() public view {
        bytes memory noOpReturnTxnHex = hex"0100000001abcdef"; // Replace with a valid raw Bitcoin transaction hex without OP_RETURN
        BitcoinTxnParser.TransactionMetadata memory metadata = client.decodeTransactionMetadata(noOpReturnTxnHex);
    }
}
