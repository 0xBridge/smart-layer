// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BLS} from "../../src/libraries/BLS.sol";

library BLSSignatureAggregation {
    // BN254 curve parameters for G1
    uint256 private constant P = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    error AdditionFailed();

    function aggregateSignatures(
        uint256[2][] memory signatures,
        uint256[4][] memory publicKeys,
        bytes32 domain,
        bytes memory message
    ) internal view returns (uint256[2] memory result) {
        require(signatures.length > 0, "Empty signatures");

        // Reduce first signature coordinates modulo P
        result = [signatures[0][0] % P, signatures[0][1] % P];

        // Add remaining signatures
        for (uint256 i = 1; i < signatures.length; i++) {
            // Reduce next signature coordinates modulo P
            uint256[2] memory nextPoint = [signatures[i][0] % P, signatures[i][1] % P];

            bool success;
            (success, result) = pointAdd(result, nextPoint);
            if (!success) revert AdditionFailed();
        }
    }

    function pointAdd(uint256[2] memory p1, uint256[2] memory p2)
        internal
        view
        returns (bool success, uint256[2] memory result)
    {
        uint256[4] memory input;
        input[0] = p1[0];
        input[1] = p1[1];
        input[2] = p2[0];
        input[3] = p2[1];

        assembly {
            // Call the bn256Add precompile
            success :=
                staticcall(
                    gas(), // Forward all gas
                    6, // The bn256Add precompile address
                    input, // Input array start
                    0x80, // Input size (4 * 32 bytes)
                    result, // Output array start
                    0x40 // Output size (2 * 32 bytes)
                )

            // Check both success of the call and the returned data
            if iszero(success) {
                // If the call failed, revert
                revert(0, 0)
            }
        }

        // Additional validation that the result is within bounds
        require(result[0] < P && result[1] < P, "Result out of bounds");
    }

    function reduceModP(uint256[2] memory point) internal pure returns (uint256[2] memory) {
        return [point[0] % P, point[1] % P];
    }
}
