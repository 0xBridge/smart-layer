// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {eBTC} from "../src/eBTC.sol";

/**
 * @title DeployEBTC
 * @notice Script to deploy the eBTC token with proxy
 * @dev Implements upgradeability via ERC1967Proxy
 */
contract DeployEBTC is Script {
    /**
     * @notice Main deployment function
     * @dev Deploys both implementation and proxy contracts
     * @return proxy_ Address of the deployed proxy
     * @return implementation_ Address of the deployed implementation
     */
    function run() external returns (address proxy_, address implementation_) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address minter = vm.envAddress("ADMIN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        eBTC implementation = new eBTC();

        // Encode initialization data
        bytes memory initData = abi.encodeCall(eBTC.initialize, minter);

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        vm.stopBroadcast();

        return (address(proxy), address(implementation));
    }
}
