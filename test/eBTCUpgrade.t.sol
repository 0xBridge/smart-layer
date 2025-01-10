// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {eBTC} from "../src/eBTC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {eBTCV2, MockNonUUPS, ReentrantUpgrader} from "./mocks/eBTCV2.sol";

contract eBTCUpgradeTest is Test {
    eBTC public implementation;
    eBTC public proxy;
    eBTCV2 public implementationV2;

    address public admin;
    address public minter;
    address public user1;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    event Upgraded(address indexed implementation);

    function setUp() public {
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        user1 = makeAddr("user1");

        vm.startPrank(admin);

        // Deploy V1
        implementation = new eBTC();

        bytes memory initData = abi.encodeWithSelector(eBTC.initialize.selector, minter);

        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);

        proxy = eBTC(address(proxyContract));

        // Deploy V2 (but don't upgrade yet)
        implementationV2 = new eBTCV2();

        vm.stopPrank();
    }

    // Basic Upgrade Tests
    function test_SuccessfulUpgrade() public {
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));

        // Test V1 functionality still works
        vm.prank(minter);
        proxy.mint(user1, 1000);
        assertEq(proxy.balanceOf(user1), 1000);

        // Test V2 functionality
        eBTCV2(address(proxy)).setNewVariable(42);
        assertEq(eBTCV2(address(proxy)).newVariable(), 42);
    }

    function testFail_UpgradeByNonAdmin() public {
        vm.prank(user1);
        proxy.upgradeTo(address(implementationV2));
    }

    // State Preservation Tests
    function test_StatePreservationAfterUpgrade() public {
        // Set initial state
        vm.prank(minter);
        proxy.mint(user1, 1000);

        // Upgrade
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));

        // Verify state is preserved
        assertEq(proxy.balanceOf(user1), 1000);
        assertTrue(proxy.hasRole(MINTER_ROLE, minter));
        assertTrue(proxy.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    // Event Tests
    function test_UpgradeEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit Upgraded(address(implementationV2));
        proxy.upgradeTo(address(implementationV2));
    }

    // Security Tests
    function testFail_UpgradeToNonContract() public {
        vm.prank(admin);
        proxy.upgradeTo(address(0x123)); // Non-contract address
    }

    function testFail_UpgradeToNonUUPS() public {
        // Deploy a non-UUPS contract
        MockNonUUPS nonUUPS = new MockNonUUPS();

        vm.prank(admin);
        proxy.upgradeTo(address(nonUUPS));
    }

    // Implementation Contract Tests
    function test_ImplementationContractIsLocked() public {
        vm.expectRevert();
        implementation.initialize(minter);
    }

    // Complex Upgrade Scenario Tests
    function test_MultipleUpgrades() public {
        // First upgrade
        vm.startPrank(admin);
        proxy.upgradeTo(address(implementationV2));

        // Deploy and upgrade to V3
        eBTCV2 implementationV3 = new eBTCV2();
        proxy.upgradeTo(address(implementationV3));
        vm.stopPrank();

        // Verify functionality still works
        vm.prank(minter);
        proxy.mint(user1, 1000);
        assertEq(proxy.balanceOf(user1), 1000);
    }

    // Role Management After Upgrade
    function test_RoleManagementAfterUpgrade() public {
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));

        // Admin should still be able to grant roles
        vm.prank(admin);
        proxy.grantRole(MINTER_ROLE, user1);

        assertTrue(proxy.hasRole(MINTER_ROLE, user1));
    }

    // Gas Tests
    function test_UpgradeGasUsage() public {
        vm.prank(admin);
        uint256 gasBefore = gasleft();
        proxy.upgradeTo(address(implementationV2));
        uint256 gasUsed = gasBefore - gasleft();
        assertTrue(gasUsed < 100000); // Adjust threshold as needed
    }

    // Edge Cases and Boundary Tests
    function testFail_ReentrantUpgrade() public {
        ReentrantUpgrader attacker = new ReentrantUpgrader(proxy);

        vm.prank(admin);
        proxy.upgradeTo(address(attacker));
    }

    function test_UpgradeWithMaxGasPrice() public {
        vm.fee(type(uint256).max); // Set max gas price
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));
        // Should succeed regardless of gas price
    }

    // Functionality Preservation Tests
    function test_PermitFunctionalityAfterUpgrade() public {
        // Perform upgrade
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));

        // Test permit functionality still works
        address owner = address(0x1);
        address spender = address(0x2);
        uint256 value = 1000;
        uint256 deadline = block.timestamp + 1 days;
        uint8 v = 27;
        bytes32 r = bytes32(uint256(1));
        bytes32 s = bytes32(uint256(2));

        vm.expectRevert(); // Should revert with invalid signature
        proxy.permit(owner, spender, value, deadline, v, r, s);
    }

    function test_BurnFunctionalityAfterUpgrade() public {
        // Mint some tokens before upgrade
        vm.prank(minter);
        proxy.mint(minter, 1000);

        // Perform upgrade
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));

        // Test burn functionality
        vm.prank(minter);
        proxy.burn(500);

        assertEq(proxy.balanceOf(minter), 500);
    }

    // Negative Tests
    function testFail_UpgradeToZeroAddress() public {
        vm.prank(admin);
        proxy.upgradeTo(address(0));
    }

    function testFail_UnauthorizedInitializeAfterUpgrade() public {
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));

        vm.prank(user1);
        eBTCV2(address(proxy)).initialize(minter);
    }

    // Complex Scenarios
    function test_UpgradeUnderLoad() public {
        // Simulate heavy contract usage
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(minter);
            proxy.mint(user1, 1);
        }

        // Perform upgrade during heavy usage
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));

        // Verify state after upgrade
        assertEq(proxy.balanceOf(user1), 100);
    }

    function test_UpgradeWithPendingTransactions() public {
        // Setup initial state
        vm.prank(minter);
        proxy.mint(user1, 1000);

        // Approve spending
        vm.prank(user1);
        proxy.approve(address(0x3), 500);

        // Perform upgrade
        vm.prank(admin);
        proxy.upgradeTo(address(implementationV2));

        // Verify allowances are preserved
        assertEq(proxy.allowance(user1, address(0x3)), 500);
    }
}
