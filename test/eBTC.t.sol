// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {eBTC} from "../src/eBTC.sol";
import {eBTCV2, MockNonUUPS, ReentrantUpgrader} from "./mocks/eBTCV2.sol";

contract eBTCTest is Test {
    eBTC public implementation;
    eBTC public proxy;
    eBTCV2 public implementationV2;

    address public admin;
    address public minter;
    address public user1;
    address public user2;
    uint256 public user1PrivateKey;
    uint256 public user2PrivateKey;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        // Generate test addresses
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        (user1, user1PrivateKey) = makeAddrAndKey("user1");
        (user2, user2PrivateKey) = makeAddrAndKey("user2");

        vm.startPrank(admin);

        // Deploy implementation
        implementation = new eBTC();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(eBTC.initialize.selector, minter);

        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);

        proxy = eBTC(address(proxyContract));

        // Deploy V2 (but don't upgrade yet)
        implementationV2 = new eBTCV2();

        vm.stopPrank();
    }

    // Initialization Tests
    function test_Initialization() public {
        assertEq(proxy.name(), "Extended Bitcoin Token");
        assertEq(proxy.symbol(), "eBTC");
        assertTrue(proxy.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(proxy.hasRole(MINTER_ROLE, minter));
    }

    function testFail_ReinitializeProxy() public {
        vm.prank(admin);
        proxy.initialize(minter);
    }

    function testFail_InitializeImplementation() public {
        vm.prank(admin);
        implementation.initialize(minter);
    }

    // Access Control Tests
    function test_AdminCanGrantRole() public {
        vm.prank(admin);
        proxy.grantRole(MINTER_ROLE, user1);
        assertTrue(proxy.hasRole(MINTER_ROLE, user1));
    }

    function testFail_NonAdminCannotGrantRole() public {
        vm.prank(user1);
        proxy.grantRole(MINTER_ROLE, user2);
    }

    // Minting Tests
    function test_MinterCanMint() public {
        vm.prank(minter);
        proxy.mint(user1, 1000);
        assertEq(proxy.balanceOf(user1), 1000);
    }

    function testFail_NonMinterCannotMint() public {
        vm.prank(user1);
        proxy.mint(user1, 1000);
    }

    // Burning Tests
    function test_MinterCanBurn() public {
        vm.startPrank(minter);
        proxy.mint(minter, 1000);
        proxy.burn(500);
        vm.stopPrank();
        assertEq(proxy.balanceOf(minter), 500);
    }

    function testFail_NonMinterCannotBurn() public {
        vm.startPrank(minter);
        proxy.mint(user1, 1000);
        vm.stopPrank();

        vm.prank(user1);
        proxy.burn(500);
    }

    // Transfer Tests
    function test_TransferBetweenUsers() public {
        vm.prank(minter);
        proxy.mint(user1, 1000);

        vm.prank(user1);
        proxy.transfer(user2, 500);

        assertEq(proxy.balanceOf(user1), 500);
        assertEq(proxy.balanceOf(user2), 500);
    }

    function testFail_TransferWithInsufficientBalance() public {
        vm.prank(minter);
        proxy.mint(user1, 100);

        vm.prank(user1);
        proxy.transfer(user2, 200);
    }

    // Approval and TransferFrom Tests
    function test_ApproveAndTransferFrom() public {
        vm.prank(minter);
        proxy.mint(user1, 1000);

        vm.prank(user1);
        proxy.approve(user2, 500);

        vm.prank(user2);
        proxy.transferFrom(user1, user2, 500);

        assertEq(proxy.balanceOf(user1), 500);
        assertEq(proxy.balanceOf(user2), 500);
    }

    function testFail_TransferFromWithoutApproval() public {
        vm.prank(minter);
        proxy.mint(user1, 1000);

        vm.prank(user2);
        proxy.transferFrom(user1, user2, 500);
    }

    // Permit Tests
    function test_Permit() public {
        uint256 value = 1000;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                user1,
                user2,
                value,
                proxy.nonces(user1),
                deadline
            )
        );

        bytes32 domainSeparator = proxy.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, digest);

        proxy.permit(user1, user2, value, deadline, v, r, s);
        assertEq(proxy.allowance(user1, user2), value);
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

    // Events Tests
    function test_TransferEvent() public {
        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, 1000);
        proxy.mint(user1, 1000);
    }

    function test_ApprovalEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Approval(user1, user2, 500);
        proxy.approve(user2, 500);
    }

    // Edge Cases
    function test_ZeroTransfer() public {
        vm.prank(user1);
        assertTrue(proxy.transfer(user2, 0));
    }

    function test_TransferToSelf() public {
        vm.prank(minter);
        proxy.mint(user1, 1000);

        vm.prank(user1);
        proxy.transfer(user1, 500);
        assertEq(proxy.balanceOf(user1), 1000);
    }

    function testFail_BurnMoreThanBalance() public {
        vm.startPrank(minter);
        proxy.mint(minter, 1000);
        proxy.burn(2000);
    }

    // Gas Tests
    function test_TransferGas() public {
        vm.prank(minter);
        proxy.mint(user1, 1000);

        vm.prank(user1);
        uint256 gasBefore = gasleft();
        proxy.transfer(user2, 100);
        uint256 gasUsed = gasBefore - gasleft();
        assertTrue(gasUsed < 60000); // Adjust threshold as needed
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
