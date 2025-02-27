// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {eBTC} from "../src/eBTC.sol";
import {eBTCManager} from "../src/eBTCManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console} from "forge-std/Script.sol";

/**
 * @title DeterministicTokenDeployer
 * @notice Factory contract that handles deterministic deployment using CREATE2
 * @dev Enables predictable addresses for token and manager contracts across chains
 */
contract DeterministicTokenDeployer is Script {
    // Constants
    address internal constant OWNER_ADDRESS = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;

    // Events
    event TokenDeployed(address indexed tokenAddress);
    event TokenManagerDeployed(address indexed tokenManager, address owner);

    /**
     * @notice Main deployment function
     * @dev Deploys both eBTCManager and eBTC token with deterministic addresses
     */
    function run() public {
        string memory rpcUrl = vm.envString("CORE_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);

        uint256 deployerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console.log("Deployer address: ", OWNER_ADDRESS);
        bytes32 salt = hex"457874656e64656420426974636f696e20546f6b656e"; // "Extended Bitcoin Token"
        // Deploy the eBTCManager contract
        address eBTCManagerInstance = deployEBTCManager(OWNER_ADDRESS, salt);
        address eBTCToken = deployToken(eBTCManagerInstance, salt);
        console.log("eBTCManagerInstance: ", eBTCManagerInstance);
        console.log("eBTCToken proxy: ", eBTCToken);
        vm.stopBroadcast();
    }

    /**
     * @notice Deploys the token using CREATE2
     * @param owner_ Address that will manage the token
     * @param salt_ Unique salt for CREATE2 deployment
     * @return proxyAddress Address of the deployed token proxy
     */
    function deployToken(address owner_, bytes32 salt_) public returns (address proxyAddress) {
        bytes memory bytecode = _generateEBTCBytecode(owner_);

        assembly {
            proxyAddress := create2(0, add(bytecode, 32), mload(bytecode), salt_)
        }

        if (proxyAddress == address(0)) {
            revert("Failed to deploy token");
        }

        emit TokenDeployed(proxyAddress);
    }

    /**
     * @notice Generates the bytecode for the token contract
     * @param owner_ Address that will manage the token
     * @return Bytecode for the token contract
     */
    function _generateEBTCBytecode(address owner_) internal returns (bytes memory) {
        address tokenImplementation = address(new eBTC());
        // Generate initialization data
        bytes memory initData = abi.encodeWithSelector(eBTC.initialize.selector, owner_);
        // Generate proxy constructor data
        return (abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(tokenImplementation, initData)));
    }

    /**
     * @notice Deploys the eBTCManager using CREATE2
     * @param owner_ Address that will own the manager
     * @param salt_ Unique salt for CREATE2 deployment
     * @return eBTCManagerInstance Address of the deployed manager
     */
    function deployEBTCManager(address owner_, bytes32 salt_) public returns (address eBTCManagerInstance) {
        bytes memory bytecode = _generateEBTCManagerBytecode(owner_);
        assembly {
            eBTCManagerInstance := create2(0, add(bytecode, 32), mload(bytecode), salt_)
        }

        if (eBTCManagerInstance == address(0)) {
            revert("Failed to deploy eBTCManagerInstance");
        }

        emit TokenManagerDeployed(eBTCManagerInstance, owner_);
    }

    /**
     * @notice Generates the bytecode for the eBTCManager contract
     * @param owner_ Address that will own the manager
     * @return Bytecode for the manager contract
     */
    function _generateEBTCManagerBytecode(address owner_) internal pure returns (bytes memory) {
        bytes memory bytecode = type(eBTCManager).creationCode;
        return abi.encodePacked(bytecode, abi.encode(owner_));
    }
}
