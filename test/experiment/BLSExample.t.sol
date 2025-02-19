// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {BLSSignatureAggregation} from "./BLSSignatureAggregation.sol";

contract BLSExample is Test {
    using BLSSignatureAggregation for *;

    bytes32 private constant DOMAIN = keccak256("TasksManager");

    function generateAggregatedSignature() public view returns (uint256[2] memory) {
        // Your input values
        string memory proofOfTask = "QmWX8fknscwu1r7rGRgQuyqCEBhcsfHweNULMEc3vzpUjP";
        bytes memory data = hex"4920616d2049726f6e6d616e21"; // "I am Ironman!"
        address performerAddress = 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE;
        uint16 taskDefinitionId = 0;
        bool isApproved = true;
        address attestationCenter = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;
        uint256 amoyChainId = 80002;

        // 1. Create the vote hash
        bytes32 voteHash = keccak256(
            abi.encode(
                proofOfTask, data, performerAddress, taskDefinitionId, attestationCenter, amoyChainId, isApproved
            )
        );

        // 2. Create message input for BLS signing
        bytes memory messageToSign = abi.encode(voteHash);

        // 3. Example individual BLS signatures (these would normally be generated off-chain)
        uint256[2][] memory signatures = new uint256[2][](2);
        // Example signature points for attester2 and attester3
        signatures[0] = [
            105337217310551818201122975635238787085604731100592555408698077011315513051746,
            17957045833089387606976709430251791631060107528517785158462291114328597599447
        ];
        signatures[1] = [
            35633234741691183105698879148857474989440869452945459970727917366913157335431,
            52077396078700498411101782280167467214158436210166580840963600551555360714507
        ];

        // 4. Example public keys (these would be registered in the contract)
        uint256[4][] memory publicKeys = new uint256[4][](2);
        // Example public key points for attester2 and attester3
        publicKeys[0] = [
            11821926051431420860601847688357774338454532808275600227002150110236814174809,
            2116700588125445636991086224320730643155475405035524838425443323593959711952,
            9795607949835180714015276978935119355980602384163973200134652620796912864594,
            15034574801356701413144808187136093970939492042984437924107452366909741414251
        ];
        publicKeys[1] = [
            13543457386728228575374355720245613197770756039695313667384985952595462085510,
            18934814890929371195253848620335296006458803040803704763498097276389019560639,
            20810444859681743345821498001887961904833007030331713589680121976412306591021,
            14890342091173553908499580082310635313783893191526877907776902154616088950354
        ];

        // 5. Generate aggregated signature
        uint256[2] memory taSignature =
            BLSSignatureAggregation.aggregateSignatures(signatures, publicKeys, DOMAIN, messageToSign);
        console.log(taSignature[0]);
        console.log(taSignature[1]);

        return taSignature;
    }

    // Function to verify if our generated signature matches the provided one
    function verifyAgainstKnownSignature() public view returns (bool) {
        uint256[2] memory generatedSignature = generateAggregatedSignature();
        console.log(generatedSignature[0]);
        console.log(generatedSignature[1]);
        uint256[2] memory knownSignature = [
            19645558472345704978511871013628884473537764836288391634501264483848712294175,
            9290822072904786298812575352542794224867844172376967240593705323173043420837
        ];

        // return (generatedSignature[0] == knownSignature[0] && generatedSignature[1] == knownSignature[1]);
    }

    // Helper function to convert a bytes signature to BLS point format
    function convertECDSAtoBLSPoint(bytes memory ecdsaSig) public pure returns (uint256[2] memory) {
        require(ecdsaSig.length == 65, "Invalid ECDSA signature length");

        // Extract r, s values from the ECDSA signature
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(ecdsaSig, 32))
            s := mload(add(ecdsaSig, 64))
        }

        // Convert to BLS format (this is a simplified example)
        return [uint256(r), uint256(s)];
    }

    // Function to demonstrate conversion of your provided signatures
    function testConvertProvidedSignatures() public pure returns (uint256[2][3] memory) {
        uint256[2][3] memory converted;

        // Convert task performer signature
        bytes memory tpSig =
            hex"e4a74f4cf94b5056483d604eb56a6a31f7791f14f0dcf1aaba7c8b6656b39d763ee2054aa2ef9ddd4a60a2b34900a40e12af2fba6a973a9d994f3686efb44a2a1c";
        converted[0] = convertECDSAtoBLSPoint(tpSig);
        console.log(converted[0][0]);
        console.log(converted[0][1]);

        // Convert attester2 signature
        bytes memory att2Sig =
            hex"e8e2c08f722aa4e91f3c7f86234afc7c92599e70d6353fe947e819e6e97f4a6227b353e885d0613a97a052ce1d071a15f4ee9f90710cb40685a83085374e14d71c";
        converted[1] = convertECDSAtoBLSPoint(att2Sig);
        console.log(converted[1][0]);
        console.log(converted[1][1]);

        // Convert attester3 signature
        bytes memory att3Sig =
            hex"4ec7b236ba4a509683d952c2220c09449f3551abac77ea8651cdadb5d5ac89877322c2fa7810f75e467c7c739017fd0be3b8b4a9211532c21dd87d760cc16f0b1b";
        converted[2] = convertECDSAtoBLSPoint(att3Sig);
        console.log(converted[2][0]);
        console.log(converted[2][1]);

        return converted;
    }

    function signatureAggregation() public {
        uint256[2][] memory signatures = new uint256[2][](2);

        // Input signature points
        signatures[0] = [
            105337217310551818201122975635238787085604731100592555408698077011315513051746,
            17957045833089387606976709430251791631060107528517785158462291114328597599447
        ];

        signatures[1] = [
            35633234741691183105698879148857474989440869452945459970727917366913157335431,
            52077396078700498411101782280167467214158436210166580840963600551555360714507
        ];

        // Log original points
        console.log("Original Point 1:");
        console.log("  x:", signatures[0][0]);
        console.log("  y:", signatures[0][1]);

        console.log("Original Point 2:");
        console.log("  x:", signatures[1][0]);
        console.log("  y:", signatures[1][1]);

        // Get reduced points
        uint256[2] memory reduced1 = BLSSignatureAggregation.reduceModP(signatures[0]);
        uint256[2] memory reduced2 = BLSSignatureAggregation.reduceModP(signatures[1]);

        console.log("Reduced Point 1:");
        console.log("  x:", reduced1[0]);
        console.log("  y:", reduced1[1]);

        console.log("Reduced Point 2:");
        console.log("  x:", reduced2[0]);
        console.log("  y:", reduced2[1]);

        // Try adding reduced points
        (bool success, uint256[2] memory addResult) = BLSSignatureAggregation.pointAdd(reduced1, reduced2);

        console.log("Direct addition success:", success);
        if (success) {
            console.log("Addition result:");
            console.log("  x:", addResult[0]);
            console.log("  y:", addResult[1]);
        }

        // Setup minimal context for full aggregation
        uint256[4][] memory publicKeys = new uint256[4][](2);
        bytes32 domain = keccak256("test");
        bytes memory message = "test";

        // Try full aggregation
        uint256[2] memory result = BLSSignatureAggregation.aggregateSignatures(signatures, publicKeys, domain, message);

        console.log("Final aggregated signature:");
        console.log("  x:", result[0]);
        console.log("  y:", result[1]);

        // Compare with known good signature
        uint256[2] memory knownSignature = [
            19645558472345704978511871013628884473537764836288391634501264483848712294175,
            9290822072904786298812575352542794224867844172376967240593705323173043420837
        ];

        bool matches = (result[0] == knownSignature[0] && result[1] == knownSignature[1]);
        console.log("Matches known signature:", matches);
    }
}
