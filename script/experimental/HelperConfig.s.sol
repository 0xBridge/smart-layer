// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address stargatePoolUsdc;
        address usdc;
        address account;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant POLYGON_MAINNET_CHAIN_ID = 137;
    uint256 constant ARB_SEPOLIA_CHAIN_ID = 421614;
    uint256 constant ARB_MAINNET_CHAIN_ID = 42161;
    uint256 constant BASE_MAINNET_CHAIN_ID = 8453;
    uint256 constant OP_MAINNET_CHAIN_ID = 10;

    uint32 constant ETH_MAINNET_ENDPOINT_ID = 30101;
    uint32 constant ETH_SEPOLIA_ENDPOINT_ID = 40161;
    uint32 constant POLYGON_MAINNET_ENDPOINT_ID = 30109;
    uint32 constant ARB_SEPOLIA_ENDPOINT_ID = 40231;
    uint32 constant ARB_MAINNET_ENDPOINT_ID = 30110;
    uint32 constant BASE_MAINNET_ENDPOINT_ID = 30184;
    uint32 constant OP_MAINNET_ENDPOINT_ID = 30111;

    // Update the BURNER_WALLET to your burner wallet!
    address constant BURNER_WALLET = 0x47D1111fEC887a7BEb7839bBf0E1b3d215669D86;
    // address constant FOUNDRY_DEFAULT_WALLET = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    // address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => uint32) public chainId_endpointId;
    mapping(uint32 chainId => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        chainId_endpointId[ETH_SEPOLIA_CHAIN_ID] = ETH_SEPOLIA_ENDPOINT_ID;
        chainId_endpointId[ETH_MAINNET_CHAIN_ID] = ETH_MAINNET_ENDPOINT_ID;
        chainId_endpointId[POLYGON_MAINNET_CHAIN_ID] = POLYGON_MAINNET_ENDPOINT_ID;
        chainId_endpointId[ARB_SEPOLIA_CHAIN_ID] = ARB_SEPOLIA_ENDPOINT_ID;
        chainId_endpointId[ARB_MAINNET_CHAIN_ID] = ARB_MAINNET_ENDPOINT_ID;
        chainId_endpointId[BASE_MAINNET_CHAIN_ID] = BASE_MAINNET_ENDPOINT_ID;
        chainId_endpointId[OP_MAINNET_CHAIN_ID] = OP_MAINNET_ENDPOINT_ID;

        networkConfigs[ETH_SEPOLIA_ENDPOINT_ID] = getEthSepoliaConfig();
        networkConfigs[ETH_MAINNET_ENDPOINT_ID] = getEthMainnetConfig();
        networkConfigs[POLYGON_MAINNET_ENDPOINT_ID] = getPolygonMainnetConfig();
        networkConfigs[ARB_SEPOLIA_ENDPOINT_ID] = getArbSepoliaConfig();
        networkConfigs[ARB_MAINNET_ENDPOINT_ID] = getArbMainnetConfig();
        networkConfigs[BASE_MAINNET_ENDPOINT_ID] = getBaseMainnetConfig();
        networkConfigs[OP_MAINNET_ENDPOINT_ID] = getOPMainnetConfig();
    }

    function getConfig() public view returns (NetworkConfig memory) {
        uint32 endpointId = chainId_endpointId[block.chainid];
        return getConfigByChainId(endpointId);
    }

    function getConfigByChainId(uint32 endpointId) public view returns (NetworkConfig memory) {
        if (networkConfigs[endpointId].stargatePoolUsdc != address(0)) {
            return networkConfigs[endpointId];
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIGS
    //////////////////////////////////////////////////////////////*/
    function getEthMainnetConfig() public pure returns (NetworkConfig memory) {
        // This is v7
        return NetworkConfig({
            stargatePoolUsdc: 0xc026395860Db2d07ee33e05fE50ed7bD583189C7,
            usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            account: BURNER_WALLET
        });
    }

    function getEthSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            stargatePoolUsdc: 0xa4e97dFd56E0E30A2542d666Ef04ACC102310083,
            usdc: 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590,
            account: BURNER_WALLET
        });
    }

    function getArbSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            stargatePoolUsdc: 0x0d7aB83370b492f2AB096c80111381674456e8d8,
            usdc: 0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773,
            account: BURNER_WALLET
        });
    }

    function getPolygonMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            stargatePoolUsdc: 0x9Aa02D4Fae7F58b8E8f34c66E756cC734DAc7fe4,
            usdc: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359,
            account: BURNER_WALLET
        });
    }

    function getArbMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            stargatePoolUsdc: 0xe8CDF27AcD73a434D661C84887215F7598e7d0d3,
            usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            account: BURNER_WALLET
        });
    }

    function getBaseMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            stargatePoolUsdc: 0x27a16dc786820B16E5c9028b75B99F6f604b5d26,
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            account: BURNER_WALLET
        });
    }

    function getOPMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            stargatePoolUsdc: 0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0,
            usdc: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
            account: BURNER_WALLET
        });
    }
}
