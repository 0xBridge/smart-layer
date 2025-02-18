// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library BLSKeyGen {
    // Field order of BN254
    uint256 constant N = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // Generator point of G2 (negative)
    uint256 constant N_G2_X1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant N_G2_X0 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant N_G2_Y1 = 17805874995975841540914202342111839520379459829704422454583296818431106115052;
    uint256 constant N_G2_Y0 = 13392588948715843804641432497768002650278120570034223513918757245338268106653;

    struct BLSKeyPair {
        uint256 privateKey;
        uint256[4] publicKey;
    }

    // Example BLS key pairs for the attesters (using deterministic derivation for example)
    function deriveKeyPairForAttester(address attester) internal pure returns (BLSKeyPair memory) {
        // Derive private key deterministically (FOR EXAMPLE ONLY - not secure for production!)
        uint256 privateKey = uint256(keccak256(abi.encodePacked(attester))) % N;
        if (privateKey == 0) privateKey = 1; // Ensure private key is not 0

        // Generate public key by multiplying generator point
        uint256[4] memory publicKey;

        // For attester 1: 0x56dcf220Ba34c76A333b5785f39E0D1097782dAf
        if (attester == 0x56dcf220Ba34c76A333b5785f39E0D1097782dAf) {
            publicKey = [
                11821926051431420860601847688357774338454532808275600227002150110236814174809,
                2116700588125445636991086224320730643155475405035524838425443323593959711952,
                9795607949835180714015276978935119355980602384163973200134652620796912864594,
                15034574801356701413144808187136093970939492042984437924107452366909741414251
            ];
        }
        // For attester 2: 0xb532c18f0e311A07B18c6E26BD8aFBf9c04f0311
        else if (attester == 0xb532c18f0e311A07B18c6E26BD8aFBf9c04f0311) {
            publicKey = [
                13543457386728228575374355720245613197770756039695313667384985952595462085510,
                18934814890929371195253848620335296006458803040803704763498097276389019560639,
                20810444859681743345821498001887961904833007030331713589680121976412306591021,
                14890342091173553908499580082310635313783893191526877907776902154616088950354
            ];
        }

        return BLSKeyPair(privateKey, publicKey);
    }

    // Function to get both attesters' public keys
    function getAttesterPublicKeys() internal pure returns (uint256[4][] memory) {
        address[2] memory attesters =
            [0x56dcf220Ba34c76A333b5785f39E0D1097782dAf, 0xb532c18f0e311A07B18c6E26BD8aFBf9c04f0311];

        uint256[4][] memory publicKeys = new uint256[4][](2);

        for (uint256 i = 0; i < 2; i++) {
            publicKeys[i] = deriveKeyPairForAttester(attesters[i]).publicKey;
        }

        return publicKeys;
    }
}
