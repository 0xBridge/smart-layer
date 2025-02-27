// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @title Utils
 * @notice Utility contract providing file I/O operations for Forge scripts
 * @dev Extends Forge's Script functionality to streamline file operations
 */
contract Utils is Script {
    /**
     * @notice Reads JSON input file from chain-specific directory
     * @param inputFileName_ Name of the input file without extension
     * @return JSON content as string
     */
    function readInput(string memory inputFileName_) internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/input/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat(inputFileName_, ".json");
        return vm.readFile(string.concat(inputDir, chainDir, file));
    }

    /**
     * @notice Reads JSON output file from chain-specific directory
     * @param outputFileName_ Name of the output file without extension
     * @return JSON content as string
     */
    function readOutput(string memory outputFileName_) internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/output/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat(outputFileName_, ".json");
        return vm.readFile(string.concat(inputDir, chainDir, file));
    }

    /**
     * @notice Writes JSON content to chain-specific output file
     * @param outputJson_ JSON content to write
     * @param outputFileName_ Name of the output file without extension
     */
    function writeOutput(string memory outputJson_, string memory outputFileName_) internal {
        string memory outputDir = string.concat(vm.projectRoot(), "/script/output/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory outputFilePath = string.concat(outputDir, chainDir, outputFileName_, ".json");
        vm.writeJson(outputJson_, outputFilePath);
    }
}
