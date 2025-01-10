// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UpgradableBitcoinLightClient} from "../src/UpgradableBitcoinLightClient.sol";

contract DeployUpgradableBitcoinLightClient is Script {
    function run(address proxyAddress) external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        UpgradableBitcoinLightClient newImplementation = new UpgradableBitcoinLightClient();

        // Get proxy instance
        UpgradableBitcoinLightClient proxy = UpgradableBitcoinLightClient(proxyAddress);

        // Upgrade to new implementation
        proxy.upgradeTo(address(newImplementation));

        vm.stopBroadcast();

        return address(newImplementation);
    }
}
