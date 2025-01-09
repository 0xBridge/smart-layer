// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {eBTC} from "../src/eBTC.sol";

contract UpgradeEBTC is Script {
    function run(address proxyAddress) external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        eBTC newImplementation = new eBTC();

        // Get proxy instance
        eBTC proxy = eBTC(proxyAddress);

        // Upgrade to new implementation
        proxy.upgradeTo(address(newImplementation));

        vm.stopBroadcast();

        return address(newImplementation);
    }
}
