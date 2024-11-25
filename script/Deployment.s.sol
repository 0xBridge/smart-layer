// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ZeroXBTC } from "../src/0xBTC.sol";

contract Deployment is Script {

    address public zeroXBTC;
    address public wrappedBTC;
    address public minter;
    uint256 public deployer;

    function setUp() public {
        minter = vm.envAddress("EVM_MINTER");
        deployer = vm.envUint("PRIVATE_KEY");
    }
    
    function run() public {
        vm.startBroadcast(deployer);
        zeroXBTC = address( new ZeroXBTC());
        wrappedBTC = address(new ERC1967Proxy(zeroXBTC, ""));
        ZeroXBTC(wrappedBTC).initialize(minter);

        console.log("Address of 0xBTC --", zeroXBTC);
        vm.stopBroadcast();

    }
}
