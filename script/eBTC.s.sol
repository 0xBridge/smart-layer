// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {eBTC} from "../src/eBTC.sol";

contract DeployEBTC is Script {
    function run() external returns (address proxy_, address implementation_) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address minter = vm.envAddress("ADMIN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        eBTC implementation = new eBTC();

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(eBTC.initialize.selector, minter);

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        vm.stopBroadcast();

        return (address(proxy), address(implementation));
    }
}
