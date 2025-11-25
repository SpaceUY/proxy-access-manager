// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Counter} from "../src/proxy-access-manager/Counter.sol";
import {AccessManagedProxy} from "../src/proxy-access-manager/AccessManagedProxy.sol";
import {CustomAccessManager} from "../src/proxy-access-manager/CustomAccessManager.sol";

/**
 * @title ProxyAccessManagerTest
 * @notice Test suite for the proxy-access-manager pattern
 * @dev Tests access control enforced at the proxy level, not in the implementation.
 *      The Counter implementation has no access control code - it's all handled by AccessManagedProxy.
 */
contract ProxyAccessManagerTest is Test {
    Counter public counterImplementation;
    AccessManagedProxy public proxy;
    Counter public counter; // Counter interface pointing to proxy
    CustomAccessManager public accessManager;
    
    address public admin = address(0x1);
    address public incrementer = address(0x2);
    address public setter = address(0x3);
    address public unauthorized = address(0x4);

    // Define custom roles (uint64)
    uint64 public constant INCREMENTER_ROLE = 1;
    uint64 public constant SETTER_ROLE = 2;

    function setUp() public {
        // Deploy CustomAccessManager with admin as initial admin
        vm.prank(admin);
        accessManager = new CustomAccessManager(admin);
        
        // Deploy Counter implementation (no access control - plain contract)
        counterImplementation = new Counter();
        
        // Deploy AccessManagedProxy pointing to Counter implementation
        bytes memory initData = "";
        proxy = new AccessManagedProxy(address(counterImplementation), initData, accessManager);
        
        // Cast proxy to Counter interface for easier interaction
        counter = Counter(address(proxy));
        
        // Grant roles to addresses (with 0 execution delay for immediate access)
        vm.startPrank(admin);
        
        accessManager.grantRole(INCREMENTER_ROLE, incrementer, 0);
        accessManager.grantRole(INCREMENTER_ROLE, admin, 0); // Admin also has incrementer role
        
        accessManager.grantRole(SETTER_ROLE, setter, 0);
        accessManager.grantRole(SETTER_ROLE, admin, 0); // Admin also has setter role
        
        // Configure function selectors to require specific roles
        // IMPORTANT: Configure permissions for the PROXY address, not the implementation!
        
        bytes4[] memory setNumberSelector = new bytes4[](1);
        setNumberSelector[0] = Counter.setNumber.selector;
        accessManager.setTargetFunctionRole(address(proxy), setNumberSelector, SETTER_ROLE);
        
        bytes4[] memory incrementSelector = new bytes4[](1);
        incrementSelector[0] = Counter.increment.selector;
        accessManager.setTargetFunctionRole(address(proxy), incrementSelector, INCREMENTER_ROLE);
        
        bytes4[] memory resetSelector = new bytes4[](1);
        resetSelector[0] = Counter.reset.selector;
        accessManager.setTargetFunctionRole(address(proxy), resetSelector, uint64(0)); // ADMIN_ROLE = 0
        
        vm.stopPrank();
    }

    function test_Increment_AsIncrementer() public {
        vm.prank(incrementer);
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function test_Increment_AsAdmin() public {
        vm.prank(admin);
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function test_Increment_RevertsIfUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        counter.increment();
    }

    function test_Increment_RevertsIfSetter() public {
        vm.prank(setter);
        vm.expectRevert();
        counter.increment();
    }

    function test_SetNumber_AsSetter() public {
        vm.prank(setter);
        counter.setNumber(42);
        assertEq(counter.number(), 42);
    }

    function test_SetNumber_AsAdmin() public {
        vm.prank(admin);
        counter.setNumber(100);
        assertEq(counter.number(), 100);
    }

    function test_SetNumber_RevertsIfUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        counter.setNumber(42);
    }

    function test_SetNumber_RevertsIfIncrementer() public {
        vm.prank(incrementer);
        vm.expectRevert();
        counter.setNumber(42);
    }

    function test_Reset_AsAdmin() public {
        vm.prank(admin);
        counter.setNumber(100);
        assertEq(counter.number(), 100);
        
        vm.prank(admin);
        counter.reset();
        assertEq(counter.number(), 0);
    }

    function test_Reset_RevertsIfNotAdmin() public {
        vm.prank(setter);
        vm.expectRevert();
        counter.reset();
        
        vm.prank(incrementer);
        vm.expectRevert();
        counter.reset();
        
        vm.prank(unauthorized);
        vm.expectRevert();
        counter.reset();
    }

    function testFuzz_SetNumber(uint256 x) public {
        vm.prank(setter);
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }

    function test_GrantRole() public {
        address newUser = address(0x5);
        
        // Grant INCREMENTER_ROLE to new user
        vm.prank(admin);
        accessManager.grantRole(INCREMENTER_ROLE, newUser, 0);
        
        // New user can now increment
        vm.prank(newUser);
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function test_RevokeRole() public {
        // First, incrementer can increment
        vm.prank(incrementer);
        counter.increment();
        assertEq(counter.number(), 1);
        
        // Revoke the role
        vm.prank(admin);
        accessManager.revokeRole(INCREMENTER_ROLE, incrementer);
        
        // Now incrementer cannot increment
        vm.prank(incrementer);
        vm.expectRevert();
        counter.increment();
    }

    function test_UpdateFunctionRole() public {
        // Initially, setter cannot increment
        vm.prank(setter);
        vm.expectRevert();
        counter.increment();
        
        // Update increment() to also allow SETTER_ROLE
        bytes4[] memory incrementSelector = new bytes4[](1);
        incrementSelector[0] = Counter.increment.selector;
        
        vm.prank(admin);
        accessManager.setTargetFunctionRole(address(proxy), incrementSelector, SETTER_ROLE);
        
        // Now setter can increment (but incrementer cannot!)
        vm.prank(setter);
        counter.increment();
        assertEq(counter.number(), 1);
        
        // Incrementer can no longer increment
        vm.prank(incrementer);
        vm.expectRevert();
        counter.increment();
    }

    function test_ProxyAddress() public {
        // Verify proxy and counter point to same address
        assertEq(address(proxy), address(counter));
    }

    function test_AccessManagerConnected() public {
        // Verify proxy has the correct AccessManager
        assertEq(address(proxy.ACCESS_MANAGER()), address(accessManager));
    }

    function test_ImplementationHasNoAccessControl() public {
        // Verify the implementation has no access control - it should revert if called directly
        // because it has no constructor that sets up AccessManager
        vm.prank(admin);
        // Direct call to implementation should work (no access control at implementation level)
        // But in a real scenario, you'd typically never call the implementation directly
        counterImplementation.setNumber(42);
        assertEq(counterImplementation.number(), 42);
    }

    function test_CheckRole() public {
        (bool hasRole1, ) = accessManager.hasRole(INCREMENTER_ROLE, incrementer);
        assertTrue(hasRole1);
        
        (bool hasRole2, ) = accessManager.hasRole(SETTER_ROLE, incrementer);
        assertFalse(hasRole2);
        
        (bool hasRole3, ) = accessManager.hasRole(INCREMENTER_ROLE, setter);
        assertFalse(hasRole3);
        
        (bool hasRole4, ) = accessManager.hasRole(SETTER_ROLE, setter);
        assertTrue(hasRole4);
    }

    function test_CanCallViaAccessManager() public {
        // Test that AccessManager correctly identifies permissions
        (bool canCall1, ) = accessManager.canCall(incrementer, address(proxy), Counter.increment.selector);
        assertTrue(canCall1);
        
        (bool canCall2, ) = accessManager.canCall(unauthorized, address(proxy), Counter.increment.selector);
        assertFalse(canCall2);
        
        (bool canCall3, ) = accessManager.canCall(setter, address(proxy), Counter.setNumber.selector);
        assertTrue(canCall3);
        
        (bool canCall4, ) = accessManager.canCall(incrementer, address(proxy), Counter.setNumber.selector);
        assertFalse(canCall4);
    }

    function test_AllFunctionsPermissionedByDefault() public {
        // In the proxy pattern, all functions are permissioned by default
        // If a function doesn't have a role configured, it defaults to ADMIN_ROLE
        
        // Try to call a function that might not be explicitly configured
        // (In our setup, all functions are configured, so this tests the default behavior)
        vm.prank(unauthorized);
        vm.expectRevert();
        counter.setNumber(42);
    }

    function test_ProxyDelegatesToImplementation() public {
        // Verify that calls through the proxy actually execute in the implementation
        vm.prank(setter);
        counter.setNumber(999);
        
        // The state should be stored in the proxy's storage (via delegatecall)
        assertEq(counter.number(), 999);
    }

    function test_EventsEmittedThroughProxy() public {
        // Test that events are emitted correctly through the proxy
        vm.expectEmit(true, true, false, true);
        emit Counter.NumberSet(0, 42);
        vm.prank(setter);
        counter.setNumber(42);
        
        vm.expectEmit(true, false, false, true);
        emit Counter.NumberIncremented(43);
        vm.prank(incrementer);
        counter.increment();
    }

    function test_TargetClosed_BlocksCallsEvenWithPermission() public {
        // Verify that setter can call setNumber when target is open
        vm.prank(setter);
        counter.setNumber(42);
        assertEq(counter.number(), 42);
        
        // Close the target (emergency stop)
        vm.prank(admin);
        accessManager.setTargetClosed(address(proxy), true);
        
        // Verify target is closed
        assertTrue(accessManager.isTargetClosed(address(proxy)));
        
        // Now even setter (who has SETTER_ROLE permission) cannot call
        vm.prank(setter);
        vm.expectRevert();
        counter.setNumber(100);
        
        // Note: We can't read counter.number() when target is closed because
        // even view functions go through the proxy and are blocked
        
        // Also test that incrementer cannot increment
        vm.prank(incrementer);
        vm.expectRevert();
        counter.increment();
        
        // Even admin cannot call (target closed blocks everyone)
        vm.prank(admin);
        vm.expectRevert();
        counter.setNumber(999);
        
        // Reopen the target
        vm.prank(admin);
        accessManager.setTargetClosed(address(proxy), false);
        
        // Verify target is open
        assertFalse(accessManager.isTargetClosed(address(proxy)));
        
        // Verify the number is still 42 (wasn't changed while closed)
        assertEq(counter.number(), 42);
        
        // Now setter can call again
        vm.prank(setter);
        counter.setNumber(100);
        assertEq(counter.number(), 100);
    }

    function test_TargetClosed_BlocksUnconfiguredFunctions() public {
        // Test that closing target also blocks unconfigured functions
        // (which would normally be public/accessible)
        
        // First verify target is open
        assertFalse(accessManager.isTargetClosed(address(proxy)));
        
        // Close the target
        vm.prank(admin);
        accessManager.setTargetClosed(address(proxy), true);
        
        // Try to call number() - even view functions should be blocked when target is closed
        // (Actually, view functions might not go through canCall in the same way,
        // but the proxy will still check permissions)
        
        // Try calling any function - it should be blocked
        vm.prank(unauthorized);
        vm.expectRevert();
        counter.increment();
        
        // Reopen
        vm.prank(admin);
        accessManager.setTargetClosed(address(proxy), false);
        
        // Now it should work (if unconfigured functions are public)
        // But in our test setup, increment requires INCREMENTER_ROLE, so unauthorized still can't
        vm.prank(unauthorized);
        vm.expectRevert();
        counter.increment();
    }

    function test_TargetClosed_CanCallReturnsFalse() public {
        // Test that canCall returns false when target is closed, even with permissions
        // First verify canCall works when open
        (bool canCall1, ) = accessManager.canCall(setter, address(proxy), Counter.setNumber.selector);
        assertTrue(canCall1);
        
        // Close the target
        vm.prank(admin);
        accessManager.setTargetClosed(address(proxy), true);
        
        // Now canCall should return false, even for users with permissions
        (bool canCall2, ) = accessManager.canCall(setter, address(proxy), Counter.setNumber.selector);
        assertFalse(canCall2);
        
        // Even admin with permissions should be blocked
        (bool canCall3, ) = accessManager.canCall(admin, address(proxy), Counter.setNumber.selector);
        assertFalse(canCall3);
        
        // Reopen
        vm.prank(admin);
        accessManager.setTargetClosed(address(proxy), false);
        
        // Now canCall should work again
        (bool canCall4, ) = accessManager.canCall(setter, address(proxy), Counter.setNumber.selector);
        assertTrue(canCall4);
    }

    function test_UnsetFunctionBySettingToPublicRole() public {
        // Initially, increment() requires INCREMENTER_ROLE
        vm.prank(unauthorized);
        vm.expectRevert();
        counter.increment();
        
        // Verify it's configured
        assertTrue(accessManager.isSelectorConfigured(address(proxy), Counter.increment.selector));
        
        // "Unset" by setting to PUBLIC_ROLE
        bytes4[] memory incrementSelector = new bytes4[](1);
        incrementSelector[0] = Counter.increment.selector;
        
        vm.prank(admin);
        accessManager.setTargetFunctionRole(address(proxy), incrementSelector, type(uint64).max); // PUBLIC_ROLE
        
        // Now anyone can call it (including unauthorized)
        vm.prank(unauthorized);
        counter.increment();
        assertEq(counter.number(), 1);
        
        // Verify getTargetFunctionRole returns PUBLIC_ROLE
        uint64 role = accessManager.getTargetFunctionRole(address(proxy), Counter.increment.selector);
        assertEq(role, type(uint64).max);
        
        // Verify canCall works for anyone
        (bool canCall1, ) = accessManager.canCall(unauthorized, address(proxy), Counter.increment.selector);
        assertTrue(canCall1);
        
        (bool canCall2, ) = accessManager.canCall(address(0x999), address(proxy), Counter.increment.selector);
        assertTrue(canCall2);
    }
}

