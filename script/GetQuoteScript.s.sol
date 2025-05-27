// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import {Script} from "forge-std/Script.sol";
// import {console} from "forge-std/console.sol";
// import {BaseChainCoordinator} from "../src/BaseChainCoordinator.sol";

// // Minimal interface for HomeChainCoordinator, assuming a similar quote function.
// // Adjust if the actual HomeChainCoordinator has a different signature or payload structure.
// interface IHomeChainCoordinator {
//     function quote(uint32 _destChainEid, bytes memory _payload, bool _payInLzToken)
//         external
//         view
//         returns (uint256 nativeFee, uint256 lzTokenFee);
// }

// contract GetQuoteScript is Script {
//     // !!! IMPORTANT: Replace these with your actual deployed contract addresses !!!
//     address constant BASE_COORDINATOR_ADDRESS = address(0xReplaceWithBaseCoordinatorAddress);
//     address constant HOME_COORDINATOR_ADDRESS = address(0xReplaceWithHomeCoordinatorAddress);

//     // Destination EIDs for quoting - replace with actual EIDs if known
//     uint32 constant DUMMY_DEST_EID_FOR_BASE = 40161; // Example: Sepolia EID
//     uint32 constant DUMMY_DEST_EID_FOR_HOME = 40102; // Example: Arbitrum Goerli EID

//     BaseChainCoordinator baseCoordinator;
//     IHomeChainCoordinator homeCoordinator;

//     function setUp() public {
//         if (BASE_COORDINATOR_ADDRESS == address(0) || HOME_COORDINATOR_ADDRESS == address(0)) {
//             console.log("ERROR: Please replace placeholder addresses in GetQuoteScript.s.sol");
//             revert("Placeholder addresses not set");
//         }
//         baseCoordinator = BaseChainCoordinator(BASE_COORDINATOR_ADDRESS);
//         homeCoordinator = IHomeChainCoordinator(HOME_COORDINATOR_ADDRESS);
//     }

//     function run() external {
//         vm.startBroadcast();

//         // --- BaseChainCoordinator Quote ---
//         console.log("Querying BaseChainCoordinator quote...");

//         // Dummy parameters for BaseChainCoordinator.quote
//         // Payload for _burnAndUnlock is abi.encode(_amount, msg.sender, _rawTxn)
//         uint256 base_dummyAmount = 100_000_000; // e.g., 1 BTC in satoshis
//         address base_dummySender = vm.addr(1); // An arbitrary address
//         bytes memory base_dummyRawTxn = hex"01020304050607080910111213141516"; // Dummy PSBT/raw transaction data
//         bytes memory base_payload = abi.encode(base_dummyAmount, base_dummySender, base_dummyRawTxn);
//         bool base_payInLzToken = false; // Quote for native gas fee

//         (uint256 baseNativeFee, uint256 baseLzTokenFee) = baseCoordinator.quote(
//             DUMMY_DEST_EID_FOR_BASE,
//             base_payload,
//             base_payInLzToken
//         );

//         console.log("BaseChainCoordinator - Destination EID:", DUMMY_DEST_EID_FOR_BASE);
//         console.log("BaseChainCoordinator - Payload (hex):", vm.toString(base_payload));
//         console.log("BaseChainCoordinator - Quoted Native Fee:", baseNativeFee);
//         console.log("BaseChainCoordinator - Quoted LZ Token Fee:", baseLzTokenFee);

//         // --- HomeChainCoordinator Quote ---
//         console.log("\nQuerying HomeChainCoordinator quote...");

//         // Dummy parameters for HomeChainCoordinator.quote
//         // Assuming a generic payload structure; adjust as needed for actual HomeChainCoordinator
//         uint256 home_dummyValue = 98765;
//         bytes memory home_dummyData = bytes("Sample Home Payload Data");
//         bytes memory home_payload = abi.encode(home_dummyValue, home_dummyData);
//         bool home_payInLzToken = false; // Quote for native gas fee

//         (uint256 homeNativeFee, uint256 homeLzTokenFee) = homeCoordinator.quote(
//             DUMMY_DEST_EID_FOR_HOME,
//             home_payload,
//             home_payInLzToken
//         );

//         console.log("HomeChainCoordinator - Destination EID:", DUMMY_DEST_EID_FOR_HOME);
//         console.log("HomeChainCoordinator - Payload (hex):", vm.toString(home_payload));
//         console.log("HomeChainCoordinator - Quoted Native Fee:", homeNativeFee);
//         console.log("HomeChainCoordinator - Quoted LZ Token Fee:", homeLzTokenFee);

//         vm.stopBroadcast();
//     }
// }
