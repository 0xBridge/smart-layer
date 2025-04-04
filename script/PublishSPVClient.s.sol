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
        hex"0000002035e8494261827396258f28bd6a00a322ec75303ad13738369403fc980000000013cf719b096b23c16ecb0663fa81925f8fcc680af8743bdb35fa0c03382d2de3f779ee67ffff001d1beb75d6"; // Example raw header

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

       "0x000000207176513f421a8e875db378d7fd8899e29dc11acff73ca1a7d31d060000000000ecbc91fc781dc3788d444b9ab6467c1231e6a80dc67a9561e354b84a53e4ee5551baee67ffff001d22fdcbdb",
  "0x00209222018393d6f9576b2456d112837de7ab97de56a5ff3f78feeb0300000000000000b870ba24fe897f0d390a6abe658dd1caf08aef86755e8646e4df77a48445f938a0b5ee67ffff001d3508823b",
  "0x002000204067e3037783e7db383dee58c3b4b9fcc2a4e0c34f9d5b54a937c8b0000000008d4050f1df091193f78a94ece8d636502a69b08c57bd49a329c7ddb5c43fa89495adee674d220619e40ca4ac",
  "0x00000020dfa8635e4ec9f59882874bbbe4ff26bbd90a9317c35a448a982e04000000000032abe44928373289680852105e142397d7f90411ee09cef3da07de368aa478ce1eb6ee67ffff001d00370fab",
  "0x002057203f33204273cd1f50e21da6098da9c8c32470ce92ddadd2e1010000000000000099731d489a3041d553f910f78b5638dbd6e5aa0301c3a9441a0022cdcdecdf476db1ee67ffff001d063e7e45",
  "0x0060002012bf7e69e31cfe63b1440f910f493066409020443bff9a91237fdebe00000000136ea43d25b5f9639512166676e89360937bbb6a38fa6b429560c18101f0f2a3e4a8ee674d22061995274fec",
  "0x000000203446d06270b0030f0367cd47d28daec2970f5b774a8139d7f5345f8e00000000b797013a543e28bbeaacccc5712b9bf616828e119af30b458bbd3b20f395501846b2ee67ffff001d021b503a",
  "0x00000020db07c78abfdf10e2fc03a49447213c0d1d74a80c4bc846dcd9b70108000000001e1d3c9c9e786933d372d102389a11b3c85846e819c402989d10df27c28ea4df95adee67ffff001d07dc383e",
  "0x00000020f81305c2b576e456cfff2cdf28c4a3ab0827afbfa8a5f850d295adaa00000000468d3f12bc87bc57f288101877a9e49b5040963fcd99c654862f04344aded900e4a8ee67ffff001d98de41bb",
  "0x00000020fdaeda9b3a51f71c72e3fc28731710e476381bbeab12d88902d228e8000000000244655f10475000ba97945656b6a4a23a6b0a63afb6c4342bf356cab0a8e49533a4ee67ffff001d09cbc38e",
  "0x00000020954c552a4bf07f1fb1e38e851ccc0686f590a7d654dde7e40400000000000000f94b1f710003e175fac5f3f0386bf36799de1b00056523485e1cfb8baeff4b40829fee67ffff001d05cc50d3",
  "0x0060452f11f22069e93e71266b309f8d6938237a55513d7900e37de61df6d5f8000000007b272b39f2f9df01cd12188c63bba549d32213240a5e0ddee0d2fabeb18774dfd19aee674d220619c880c767",
  "0x00000020343f4fe1ffb748eff878c4109d70e8cf16e07cf1324f64738cad7fd8000000008194f210262c9b7e0bdc7641e125056952f18b632f8e639a203f289d77c487c645b2ee67ffff001d12728673",
  "0x00000020eede730c575ab2a29d18bc35bc1ab05f1ca19b67fa00c27fe9bc0697000000009beecc439a3cb941c4861c195f8a60fc679f36fae5dba1905ca7095f5261346d94adee67ffff001d1a25ca5a",
  "0x000000200d4ec1dc45f554d9a631b992208bf761c7cc6a409a45c6f8959e4ead0000000097d3eda92c58e63b4e4ceb8ae280b513559b90d007782e04269fd51914b30f84e3a8ee67ffff001d0bf3e87a",
  "0x00000020deec944f7d7684a13c54db94695e9511b9686bdc82ca6c2a2a99d0a500000000a3d476c31c6366e985014069c7b41f02e17dcc693eb25d2069dbdd35e4e4af4d32a4ee67ffff001dbfac844c",
  "0x00000020ace7b9db88a580c481901eac528629d48b5006a429eacb4fb16ea80e000000006a6e5d91253754eaadfe88a22456b32c689a4d8960509cfb0cfdf665e8594e8a819fee67ffff001d27b4b3b4",
  "0x00000020bf83beedc528c49f9ca76d5e1943d1785ad85ea7727af800fa6afc0800000000384fbb09bd3e37b1410f7fd580635f5d0f881c28075fc8248b01db801470dd3cd09aee67ffff001d219da309",
  "0x000000207e8987304e11c8011f4e4a77a6869a40ae4d2b30c2fc4b851b22d90400000000e2396ab13d3061860755bbb60493fbc2513fcde8150a55a1459cbe130ddb0f571f96ee67ffff001d919ea6e6",
  "0x00000020091c08c08be887f9a68841fcfd79e931c4e671e110c8644d0244540900000000e872c2b7490932e39f863d2034fdbe998219d26c16ce8f0237857fba75ba32216e91ee67ffff001d92d9b2fd",
  "0x00000020df000cce655037e57224097208397be864fba6402596a7f8db63220800000000bdf93abb94d85c0f5565d12f8533eea5446999b5a2081a0a51159ea552c0794ebd8cee67ffff001da36a792c",
  "0x00000020d372f22035b323c062b803599b211f2c23155c4e97f81db300000000000000009d85e8bb54afc2146ae0e5dd6e4290139bcb80e99c9ef1f1878e998769725bb90c88ee67ffff001d53181ac5",
  "0x00000022716c6bfa32f0a893e2b380e7226680b23bb5e3a4dbcccd761d16e31b000000006f034d49772934aeb5883674e39f82cda09c680d79f43cfbd0e713a81e17c6945b83ee674d220619909f7525",
  "0x00000020735b9fcc2224592fc2cfec560618a19236e4fe67fc075c80abddb60b00000000257d7bf717d652bf07cd451abad96e81e2cde4dcced018ebf376feebbe50b68ccf9aee67ffff001d8bac0767",
  "0x00000020cdbe686724810689851cb087687e8d593daea3e85143e48f493a0713000000008f3bb9174f3acb885ce11030d259f0f3c2f3dcc26a982030e27b6de365f6ac7d1e96ee67ffff001d387ce7c8",
  "0x0000002024d8508ac1a14afc79c816e5f4eb36609e605b66077e416d9822c43c000000007136c46dfa68cd5450b5f8f6995e7982342c0cda3bb30a59fdac5b7fd44b17cc6d91ee67ffff001d9a25f0b2",
  "0x0000002084b03607566b41c3a43da690da750f9d8f0452a2f40bd302fff5461e00000000b9173ef030b9c75c8dfd0f7548fd6f154154bf3325ec6ae33876620183ee8fe9bc8cee67ffff001dacc7904f",
  "0x00000020efc81307233eb98471f9ce172b72a3fbe43856a3d38cd15805fcb5c300000000ab78847a177ca1c217205e450b4a6885e70e55faa5cc0244fa93c468b4e5e2780b88ee67ffff001d727118c9",
  "0x0000002024f40744389125007fa1b07396c2c2bc12774d6643e963cd3e150a2e000000005245fb28b50619d7ed4f6c9d69ebabfd8d7cc3293d42b4be96ab1076e8be8f365a83ee67ffff001d0d559ae7",
  "0x00000020bd49978140548215ec02ec50163aca1b7d7945523f2023459c59454d000000001829303498c88708aa9326a84fa06797e006f10468287fd01f287fba60081e6ca97eee67ffff001da5495c8a",
  "0x000000202580bee2a397b72f67c88d09af954ba7a3013be575d394df6f5dc69f000000001a8cf98470df9640eee9fd479908fb08a07a96c737d95203bbf33d81acf4525af879ee67ffff001d0d6c2b2d",
  "0x000000201c4d1e793ad0f5cb7e91072989d9087ecdce296aa256cc87fe0a89b700000000279d786beee0ec92265ff0b729ddd1d2e15a1c8470a91dbf28fa7f5db6a359e24775ee67ffff001d054dced9",
  "0x0000002054b98039cbb2f403109f45be6cc03ce0513d73b0405009e60100000000000000a3975d196543f11d8940e9cde7fdb0938b7cba0313d04724e76f8532a9b8711f9670ee67ffff001d18acb770",
  "0x008076209a03d35d3b69226bce3bc5df3312a218787a245b1af7259a25d332c100000000213cbe2354cda98f6f3abbe938574bd903f0a4c6aa320685468ddbfff09f1b9be56bee674d220619b20af3fc",
  "0x000000208e5d3005986c8f3b9337c77d87eb9e1a5b703629682da23ab5943782000000003b195f9443767eb02c7a9a11dc937c1c584798b08bc40a800004fca081a02c6d5983ee67ffff001d1b1494f6",
  "0x00000020124b855186fb25afba9990f0c7587da817721de9d5a2ac59bce469d7000000005feecaea16c4ddb82b95df1ea4baeddee85803565cd08db197d68356a4515367a87eee67ffff001d02ef45ac",
  

        // Method 2: Submit using raw header
        // Uncomment to use raw header submission instead
        bytes[] memory intermediateHeaders = new bytes[](13); // No intermediate headers
        intermediateHeaders[0] =
            hex"00000020de5d7410fa8e8196680f0e6f91fb7536d07f53a90df6cb7a46ba399e000000007b53ab8fa692c4dfbf98347d8007edf0e20c89344b5101829b73e90c92a00cd34675ee67ffff001d51128e21";
        intermediateHeaders[1] =
            hex"0000002015adb8e55ef1380de0f66a533d8bb745f3c870dd403b8784e7ea4385000000007a30643b37569d4fd244ee8effed4b925d83f9c3f408c372cbf092377ce069259570ee67ffff001d0255259a";
        intermediateHeaders[2] =
            hex"000000206eec36416c632c2a7176f16e45cbecd111faf6a392a5e2127537c145000000008504743d73d82751d5ad5a75384b7f7addebd2bb15274458d9fcf513abcc7767e46bee67ffff001d257aa0c3";
        intermediateHeaders[3] =
            hex"00000020f8e170b4634876c78ada64bc603f1e7f3abd2e91879a91ce46d4a8390000000003e759094efd75fa393777ca1b595c6d001acc0c42615a5cf20296b33f1823463367ee67ffff001d15691d87";
        intermediateHeaders[4] =
            hex"0000002097aecd157468506055255e5411b1fce71b4618ef66cc8d34021691380000000083b9f7d6114149c64e52f8609d6f8dd03c44d2f1b698a218e48c617cb02156e18262ee67ffff001d215e271a";
        intermediateHeaders[5] =
            hex"00000020034bff8ce37ba15982fa60fbc57f9a95075d973d3d5f456f5777c4f0000000009c7c52beb7293510ca5f0d6b3b390e5c432a6a67473993b68f8b4f624869fa26d15dee67ffff001d14f8368a";
        intermediateHeaders[6] =
            hex"0000002092b02850d8f662d42877fd0363e610180a45a1f05f890016c294d0d0000000009e9d41dce355efdb4064de64ae9f62aa3d97247b581d2e0c31c09a5c9b4184182059ee67ffff001d74d4aa54";
        intermediateHeaders[7] =
            hex"00000020463b107775652ae4c16e91512f67f42b27f144645ddba7de43a1ccf300000000e90acb359726d70e906d377bd1a286b9dfe9c43264901ffa06ff307485f1dd476f54ee67ffff001d0e534c36";
        intermediateHeaders[8] =
            hex"000000206e0e7d753ddcb137a71636c135c54ce7720d06ec302b96f62e2f246b000000009c45e6bac5d1fc92c21763544503422920538de9d4a319fefb190eca80deef2dbe4fee67ffff001d3dd79618";
        intermediateHeaders[9] =
            hex"00000020e8ba13405b1b5345701890d017c4a156841ab8736284b94d811e2b750000000084c6bf4fd4b56e29661c297187604932ff0cf8b2ade72bbeefa570e622053c800d4bee67ffff001d357a2d82";
        intermediateHeaders[10] =
            hex"000000208d57220d14cc40e9d78d4b317425b30b4c3305637b376eabb2f26d8a000000001d57b4a26fe4ca61370b0b94df40ae9048a004d4d3273d5d69d1978964c92ba35c46ee67ffff001d0fdd1f3f";
        intermediateHeaders[11] =
            hex"00000020685eaaf7be9dd8af5a3544708184bf513095ac1f1d6b2e21c828fd1b0000000009fe18e208c965a0884555ca4eef30b1c83bffa548956cc6eb250e726b6a2b41ab41ee67ffff001d8a138304";
        intermediateHeaders[12] =
            hex"00000020081dc908153b5e6ae3d851431de279627a943382f8cdbeb1b7d0c45e0000000079cc2f80c9494cbd7797274dd6419727c3ee47258cc194fb8a32b552562407ddfa3cee67ffff001d0578b227";

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

    /**
     * @notice Helper function to publish multiple consecutive block headers
     * @param count Number of consecutive block headers to publish
     */
    // function publishMultipleHeaders(uint256 count) public {
    //     // Connect to the network
    //     string memory rpcUrl = vm.envString("AMOY_RPC_URL");
    //     _forkId = vm.createSelectFork(rpcUrl);

    //     uint256 privateKey = vm.envUint("OWNER_PRIVATE_KEY");
    //     _btcLightClient = BitcoinLightClient(BTC_LIGHT_CLIENT);

    //     vm.startBroadcast(privateKey);

    //     bytes32 prevBlockHash = _btcLightClient.getLatestHeaderHash();
    //     uint32 timestamp = BLOCK_TIMESTAMP;

    //     for (uint256 i = 0; i < count; i++) {
    //         // Increment timestamp for each block
    //         timestamp += 600; // ~10 minutes between blocks

    //         bytes32 blockHash = _btcLightClient.submitBlockHeader(
    //             BLOCK_VERSION,
    //             timestamp,
    //             DIFFICULTY_BITS,
    //             NONCE + uint32(i), // Different nonce for each block
    //             0, // Height is calculated by the contract
    //             prevBlockHash, // Previous block is the one we just submitted
    //             MERKLE_ROOT,
    //             new bytes[](0)
    //         );

    //         console.log("Submitted block #%d", i + 1);
    //         console.logBytes32(blockHash);

    //         // Update prevBlockHash for the next iteration
    //         prevBlockHash = blockHash;
    //     }

    //     vm.stopBroadcast();
    // }
}
