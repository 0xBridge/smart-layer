// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EnhancedBitcoinTxnParser} from "./libraries/EnhancedBitcoinTxnParser.sol";

contract BitcoinTxnParserExample {
    using EnhancedBitcoinTxnParser for bytes;

    // Event to emit parsed output details
    event OutputParsed(uint64 value, bytes32 scriptType, string scriptPubKeyAsm, string destinationAddress);

    // Example function to parse all outputs from a Bitcoin transaction
    function parseAllOutputs(bytes calldata rawTxn) external {
        EnhancedBitcoinTxnParser.OutputInfo[] memory outputs = EnhancedBitcoinTxnParser.parseTransactionOutputs(rawTxn);

        for (uint256 i = 0; i < outputs.length; i++) {
            emit OutputParsed(
                outputs[i].value, outputs[i].scriptType, outputs[i].scriptPubKeyAsm, outputs[i].destinationAddress
            );
        }
    }

    // Find a specific output by its script type (e.g., "v0_p2wpkh")
    function findOutputByType(bytes calldata rawTxn, string calldata typeStr)
        external
        pure
        returns (uint64 value, string memory scriptPubKeyAsm, string memory destinationAddress)
    {
        bytes32 scriptType = keccak256(abi.encodePacked(typeStr)) == keccak256(abi.encodePacked("v0_p2wpkh"))
            ? EnhancedBitcoinTxnParser.TYPE_V0_P2WPKH
            : keccak256(abi.encodePacked(typeStr)) == keccak256(abi.encodePacked("v1_p2tr"))
                ? EnhancedBitcoinTxnParser.TYPE_V1_P2TR
                : keccak256(abi.encodePacked(typeStr)) == keccak256(abi.encodePacked("op_return"))
                    ? EnhancedBitcoinTxnParser.TYPE_OP_RETURN
                    : EnhancedBitcoinTxnParser.TYPE_P2PKH;

        EnhancedBitcoinTxnParser.OutputInfo memory output =
            EnhancedBitcoinTxnParser.findOutputByType(rawTxn, scriptType);

        return (output.value, output.scriptPubKeyAsm, output.destinationAddress);
    }

    // Example of parsing your specific transaction with the provided hex
    function parseExample() external pure returns (string memory result) {
        bytes memory rawTxn =
            hex"0200000000010157499e56f75c5f0f6bd6c9c66a4ba48d928232c4f197a6a8dfbb7e48fec1b0b20300000000ffffffff041027000000000000225120b2925665f511a4ec1507d9710600be27f791f80131074c6eda5739053714f33be80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a3000144e56a8e3757f167378b38269e1ca0e1a1f124c9e0008000000000000054d000400009ca60008000000000000007bb205000000000000160014d5a028b62114136a63ebcfacf94e18536b90a1210247304402201edc33abe7cf58289a202d990f0c9dee82d0f9986b6acff76ccc1f6c0fa731440220699ccbc09f9cffa4cef1004746251128966465d8a78c687a7acbd174709f11ee0121036a43583212d54a5977f2cef457520c520ab9bf92299b2d74011ecd410bdb250600000000";

        // Parse all outputs
        EnhancedBitcoinTxnParser.OutputInfo[] memory outputs = EnhancedBitcoinTxnParser.parseTransactionOutputs(rawTxn);

        // Build a formatted output
        string memory txnDetails = "";

        for (uint256 i = 0; i < outputs.length; i++) {
            EnhancedBitcoinTxnParser.OutputInfo memory output = outputs[i];

            txnDetails = string(
                abi.encodePacked(
                    txnDetails,
                    "Output #",
                    uint2str(i),
                    ":\n",
                    "  Value: ",
                    uint2str(output.value),
                    " satoshis\n",
                    "  Type: ",
                    bytes32ToString(output.scriptType),
                    "\n",
                    "  ScriptPubKey ASM: ",
                    output.scriptPubKeyAsm,
                    "\n",
                    "  Address: ",
                    output.destinationAddress,
                    "\n\n"
                )
            );
        }

        // Get a specific output
        try EnhancedBitcoinTxnParser.findOutputByType(rawTxn, EnhancedBitcoinTxnParser.TYPE_V0_P2WPKH) returns (
            EnhancedBitcoinTxnParser.OutputInfo memory specificOutput
        ) {
            txnDetails = string(
                abi.encodePacked(
                    txnDetails,
                    "Found v0_p2wpkh output:\n",
                    "  Value: ",
                    uint2str(specificOutput.value),
                    " satoshis\n",
                    "  Address: ",
                    specificOutput.destinationAddress,
                    "\n"
                )
            );
        } catch {
            txnDetails = string(abi.encodePacked(txnDetails, "No v0_p2wpkh output found\n"));
        }

        return txnDetails;
    }

    // Helper function to convert uint to string
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }

        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }

        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }

        return string(bstr);
    }

    // Helper function to convert bytes32 to string
    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
