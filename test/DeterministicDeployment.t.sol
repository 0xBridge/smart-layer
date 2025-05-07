// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeterministicTokenDeployer} from "../script/DeterministicTokenDeployer.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeterministicDeploymentTest is Test {
    DeterministicTokenDeployer private deployer;
    HelperConfig.NetworkConfig private srcNetworkConfig;
    HelperConfig.NetworkConfig private destNetworkConfig;

    uint256 private sourceForkId;
    uint256 private destForkId;
    address private owner;
    bytes32 private constant SALT = hex"457874656e64656420426974636f696e20546f6b656e"; // "Extended Bitcoin Token"

    function setUp() public {
        deployer = new DeterministicTokenDeployer();
        owner = deployer.OWNER_ADDRESS();
        vm.deal(owner, 100 ether);

        // Setup source chain (e.g., Amoy testnet)
        string memory srcRpcUrl = vm.envString("BSC_TESTNET_RPC_URL");
        sourceForkId = vm.createSelectFork(srcRpcUrl);
        HelperConfig srcConfig = new HelperConfig();
        srcNetworkConfig = srcConfig.getConfig();

        // Setup destination chain (e.g., Core testnet)
        string memory destRpcUrl = vm.envString("CORE_TESTNET_RPC_URL");
        destForkId = vm.createSelectFork(destRpcUrl);
        HelperConfig destConfig = new HelperConfig();
        destNetworkConfig = destConfig.getConfig();
    }

    function testDeterministicDeploymentAcrossChains() public {
        // Deploy on source chain
        vm.selectFork(sourceForkId);
        vm.startPrank(owner);

        address srcManager = deployer.deployEBTCManager(owner, SALT);
        address srcToken = deployer.deployToken(srcManager, SALT);

        vm.stopPrank();

        // Store addresses from source chain
        address sourceManagerAddress = srcManager;
        address sourceTokenAddress = srcToken;

        // Deploy on destination chain
        vm.selectFork(destForkId);
        vm.startPrank(owner);

        address destManager = deployer.deployEBTCManager(owner, SALT);
        address destToken = deployer.deployToken(destManager, SALT);

        vm.stopPrank();

        // Verify addresses match across chains
        assertEq(sourceManagerAddress, destManager, "eBTCManager addresses should match across chains");
        assertEq(sourceTokenAddress, destToken, "eBTC token addresses should match across chains");
    }
}
