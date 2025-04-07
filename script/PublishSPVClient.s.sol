// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {BitcoinLightClient} from "../src/BitcoinLightClient.sol";
import {BitcoinUtils} from "../src/libraries/BitcoinUtils.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title PublishSPVClient
 * @notice Script for publishing Bitcoin block headers to the BitcoinLightClient
 * @dev Submits new block headers to keep the SPV client up-to-date
 */
contract PublishSPVClient is Script {
    address private constant BTC_LIGHT_CLIENT = 0x288f1261A71F4FE71f1f3D10bF3A4d30e17d9c82; // Replace with actual deployed address
    // Contract instance
    BitcoinLightClient internal _btcLightClient;

    // Network configuration
    HelperConfig.NetworkConfig internal _networkConfig;

    // Fork ID
    uint256 internal _forkId;

    // Alternatively, you can use a raw block header
    bytes internal constant RAW_BLOCK_HEADER =
        hex"00000020deec944f7d7684a13c54db94695e9511b9686bdc82ca6c2a2a99d0a500000000a3d476c31c6366e985014069c7b41f02e17dcc693eb25d2069dbdd35e4e4af4d32a4ee67ffff001dbfac844c"; // Example raw header

    /**
     * @notice Main function to publish a new block header
     */
    function run() public {
        // Connect to the network where the BitcoinLightClient is deployed
        string memory rpcUrl = vm.envString("AMOY_RPC_URL"); // Use the relevant network
        _forkId = vm.createSelectFork(rpcUrl);

        HelperConfig config = new HelperConfig();
        _networkConfig = config.getConfig();

        // Get the private key for broadcasting transactions
        uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");

        // Connect to the BitcoinLightClient contract
        _btcLightClient = BitcoinLightClient(BTC_LIGHT_CLIENT);

        // Get the latest block info for logging
        bytes32 latestHash = _btcLightClient.getLatestHeaderHash();
        BitcoinUtils.BlockHeader memory latestHeader = _btcLightClient.getLatestCheckpoint();
        console.log("Current latest block height:", latestHeader.height);
        console.logBytes32(latestHash);

        vm.startBroadcast(privateKey);

        // Method 1: Submit using individual parameters
        /*
        bytes32 blockHash = _btcLightClient.submitBlockHeader(
            BLOCK_VERSION,
            BLOCK_TIMESTAMP,
            DIFFICULTY_BITS,
            NONCE,
            0, // Height is calculated by the contract
            PREV_BLOCK,
            MERKLE_ROOT,
            new bytes[](0) // No intermediate headers
        );
        console.log("Submitted new block header using parameters");
        console.logBytes32(blockHash);
        */

        // Method 2: Submit using raw header
        // Uncomment to use raw header submission instead
        bytes[] memory intermediateHeaders = new bytes[](24); // No intermediate headers
        intermediateHeaders[0] =
            hex"00000020343f4fe1ffb748eff878c4109d70e8cf16e07cf1324f64738cad7fd8000000008194f210262c9b7e0bdc7641e125056952f18b632f8e639a203f289d77c487c645b2ee67ffff001d12728673",
        intermediateHeaders[1] =
                    hex"00000020eede730c575ab2a29d18bc35bc1ab05f1ca19b67fa00c27fe9bc0697000000009beecc439a3cb941c4861c195f8a60fc679f36fae5dba1905ca7095f5261346d94adee67ffff001d1a25ca5a",
        intermediateHeaders[2] =
                    hex"000000200d4ec1dc45f554d9a631b992208bf761c7cc6a409a45c6f8959e4ead0000000097d3eda92c58e63b4e4ceb8ae280b513559b90d007782e04269fd51914b30f84e3a8ee67ffff001d0bf3e87a",
        intermediateHeaders[3] =
                    hex"00000020deec944f7d7684a13c54db94695e9511b9686bdc82ca6c2a2a99d0a500000000a3d476c31c6366e985014069c7b41f02e17dcc693eb25d2069dbdd35e4e4af4d32a4ee67ffff001dbfac844c",
        intermediateHeaders[4] =
                    hex"00000020ace7b9db88a580c481901eac528629d48b5006a429eacb4fb16ea80e000000006a6e5d91253754eaadfe88a22456b32c689a4d8960509cfb0cfdf665e8594e8a819fee67ffff001d27b4b3b4",
        intermediateHeaders[5] =
                    hex"00000020bf83beedc528c49f9ca76d5e1943d1785ad85ea7727af800fa6afc0800000000384fbb09bd3e37b1410f7fd580635f5d0f881c28075fc8248b01db801470dd3cd09aee67ffff001d219da309",
        intermediateHeaders[6] =
                    hex"000000207e8987304e11c8011f4e4a77a6869a40ae4d2b30c2fc4b851b22d90400000000e2396ab13d3061860755bbb60493fbc2513fcde8150a55a1459cbe130ddb0f571f96ee67ffff001d919ea6e6",
        intermediateHeaders[7] =
                    hex"00000020091c08c08be887f9a68841fcfd79e931c4e671e110c8644d0244540900000000e872c2b7490932e39f863d2034fdbe998219d26c16ce8f0237857fba75ba32216e91ee67ffff001d92d9b2fd",
        intermediateHeaders[8] =
                    hex"00000020df000cce655037e57224097208397be864fba6402596a7f8db63220800000000bdf93abb94d85c0f5565d12f8533eea5446999b5a2081a0a51159ea552c0794ebd8cee67ffff001da36a792c",
        intermediateHeaders[9] =
                    hex"00000020d372f22035b323c062b803599b211f2c23155c4e97f81db300000000000000009d85e8bb54afc2146ae0e5dd6e4290139bcb80e99c9ef1f1878e998769725bb90c88ee67ffff001d53181ac5",
        intermediateHeaders[10] =
                    hex"00000022716c6bfa32f0a893e2b380e7226680b23bb5e3a4dbcccd761d16e31b000000006f034d49772934aeb5883674e39f82cda09c680d79f43cfbd0e713a81e17c6945b83ee674d220619909f7525",
        intermediateHeaders[11] =
                    hex"00000020735b9fcc2224592fc2cfec560618a19236e4fe67fc075c80abddb60b00000000257d7bf717d652bf07cd451abad96e81e2cde4dcced018ebf376feebbe50b68ccf9aee67ffff001d8bac0767",
        intermediateHeaders[12] =
                    hex"00000020cdbe686724810689851cb087687e8d593daea3e85143e48f493a0713000000008f3bb9174f3acb885ce11030d259f0f3c2f3dcc26a982030e27b6de365f6ac7d1e96ee67ffff001d387ce7c8",
        intermediateHeaders[13] =
                    hex"0000002024d8508ac1a14afc79c816e5f4eb36609e605b66077e416d9822c43c000000007136c46dfa68cd5450b5f8f6995e7982342c0cda3bb30a59fdac5b7fd44b17cc6d91ee67ffff001d9a25f0b2",
        intermediateHeaders[14] =
                    hex"0000002084b03607566b41c3a43da690da750f9d8f0452a2f40bd302fff5461e00000000b9173ef030b9c75c8dfd0f7548fd6f154154bf3325ec6ae33876620183ee8fe9bc8cee67ffff001dacc7904f",
        intermediateHeaders[15] =
                    hex"00000020efc81307233eb98471f9ce172b72a3fbe43856a3d38cd15805fcb5c300000000ab78847a177ca1c217205e450b4a6885e70e55faa5cc0244fa93c468b4e5e2780b88ee67ffff001d727118c9",
        intermediateHeaders[16] =
                    hex"0000002024f40744389125007fa1b07396c2c2bc12774d6643e963cd3e150a2e000000005245fb28b50619d7ed4f6c9d69ebabfd8d7cc3293d42b4be96ab1076e8be8f365a83ee67ffff001d0d559ae7",
        intermediateHeaders[17] =
                    hex"00000020bd49978140548215ec02ec50163aca1b7d7945523f2023459c59454d000000001829303498c88708aa9326a84fa06797e006f10468287fd01f287fba60081e6ca97eee67ffff001da5495c8a",
        intermediateHeaders[18] =
                    hex"000000202580bee2a397b72f67c88d09af954ba7a3013be575d394df6f5dc69f000000001a8cf98470df9640eee9fd479908fb08a07a96c737d95203bbf33d81acf4525af879ee67ffff001d0d6c2b2d",
        intermediateHeaders[19] =
                    hex"000000201c4d1e793ad0f5cb7e91072989d9087ecdce296aa256cc87fe0a89b700000000279d786beee0ec92265ff0b729ddd1d2e15a1c8470a91dbf28fa7f5db6a359e24775ee67ffff001d054dced9",
        intermediateHeaders[20] =
                    hex"0000002054b98039cbb2f403109f45be6cc03ce0513d73b0405009e60100000000000000a3975d196543f11d8940e9cde7fdb0938b7cba0313d04724e76f8532a9b8711f9670ee67ffff001d18acb770",
        intermediateHeaders[21] =
                    hex"008076209a03d35d3b69226bce3bc5df3312a218787a245b1af7259a25d332c100000000213cbe2354cda98f6f3abbe938574bd903f0a4c6aa320685468ddbfff09f1b9be56bee674d220619b20af3fc",
        intermediateHeaders[22] =
                    hex"000000208e5d3005986c8f3b9337c77d87eb9e1a5b703629682da23ab5943782000000003b195f9443767eb02c7a9a11dc937c1c584798b08bc40a800004fca081a02c6d5983ee67ffff001d1b1494f6",
        intermediateHeaders[23] =
                    hex"00000020124b855186fb25afba9990f0c7587da817721de9d5a2ac59bce469d7000000005feecaea16c4ddb82b95df1ea4baeddee85803565cd08db197d68356a4515367a87eee67ffff001d02ef45ac",
  
        bytes32 rawBlockHash = _btcLightClient.submitRawBlockHeader(RAW_BLOCK_HEADER, intermediateHeaders);
        console.log("Submitted new block header using raw data");
        console.logBytes32(rawBlockHash);

        // Get the updated latest block info
        bytes32 newLatestHash = _btcLightClient.getLatestHeaderHash();
        BitcoinUtils.BlockHeader memory newLatestHeader = _btcLightClient.getLatestCheckpoint();
        console.log("New latest block height:", newLatestHeader.height);
        console.logBytes32(newLatestHash);

        vm.stopBroadcast();
    }

}
