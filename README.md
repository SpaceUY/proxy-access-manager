# Installation

forge install foundry-rs/forge-std --no-git
forge install OpenZeppelin/openzeppelin-contracts --no-git

# Tests

forge test

# Custom Access Controller: Proxy-Based Access Management

## Overview

This document explains the rationale and implementation of the **CustomAccessManager** pattern for proxy-based access control, which solves the problem of managing public vs. restricted functions when using `AccessManager` with proxy contracts.

---

## Standard AccessManager Pattern

### How AccessManager Works

The standard `AccessManager` operates on functions that are **tagged with the `restricted` modifier**. The flow is:

1. **Target Contract**: Functions use the `restricted` modifier to indicate they should be controlled by AccessManager
2. **AccessManager Configuration**: The admin configures permissions by:
   - **Granting roles** to addresses via `grantRole()`
   - **Attaching roles to function selectors** via `setTargetFunctionRole()`
3. **Access Control**: When a restricted function is called, it checks with AccessManager if the caller has the required role

### Making Functions Public

In the standard pattern, there are two ways to make a function publicly accessible:

1. **Don't use the `restricted` modifier** - The function remains unrestricted at the contract level
2. **Use `restricted` but configure it to `PUBLIC_ROLE`** - The modifier is present, but `PUBLIC_ROLE` allows anyone to call it

Both approaches work because the `restricted` modifier is **optional** - only functions that use it are subject to AccessManager control.

---

## Proxy Access Manager Pattern

### The Approach

The **Proxy Access Manager** pattern (also known as `AccessManagedProxy`) takes a different approach:

- **No modifiers needed** in the implementation contract
- **All calls are intercepted** at the proxy level via `_delegate()`
- **Access control is centralized** - configured entirely through AccessManager, not in code
- **Implementation stays simple** - pure business logic with no access control code

This follows the idea discussed in the [OpenZeppelin Forum: AccessManagedProxy](https://forum.openzeppelin.com/t/accessmanagedproxy-is-a-good-idea/41917).

### The Problem

When using `AccessManagedProxy` with the standard `AccessManager`, there's a critical issue:

**Every function call goes through the proxy**, which checks `AccessManager.canCall()`. However, the standard `AccessManager` has a default behavior:

- **Unconfigured functions default to `ADMIN_ROLE` (role ID = 0)**
- This means **public functions get blocked** unless explicitly configured

This creates a dilemma:

1. **Whitelist every public function** - You must call `setTargetFunctionRole()` for every public function, setting it to `PUBLIC_ROLE`. This is:
   - ❌ Tedious and error-prone
   - ❌ Requires knowing all public functions upfront
   - ❌ Breaks if new public functions are added

2. **Skip checks at proxy level** - Add logic in the proxy to skip access checks for certain functions (similar to ENSURO's approach). This is:
   - ❌ **Bad design** - Access control logic becomes split between proxy and AccessManager
   - ❌ Harder to audit - permissions are scattered
   - ❌ Violates single responsibility principle

---

## CustomAccessManager: The Solution

### The Idea

The `CustomAccessManager` extends the standard `AccessManager` with one key capability:

**It can distinguish between "unconfigured" and "explicitly configured" functions.**

### How It Works

1. **Tracks Configured Selectors**: Maintains a mapping `_configuredSelectors` that records which `(target, selector)` pairs have been explicitly configured via `setTargetFunctionRole()`

2. **Override `getTargetFunctionRole()`**:
   - If a selector is **not configured** → returns `PUBLIC_ROLE` (anyone can call)
   - If a selector **is configured** → returns the explicitly set role

3. **Override `setTargetFunctionRole()`**: When setting a role, it marks the selector as "configured" in the tracking mapping

### Key Benefits

✅ **Unconfigured functions are public by default** - No need to whitelist every public function  
✅ **Explicitly configured functions use their set role** - Restricted functions work as expected  
✅ **All access control logic remains in AccessManager** - No logic split between proxy and manager  
✅ **Easy to audit** - All permissions configured in one place  
✅ **Flexible** - Can make functions public or restricted by configuration, not code  


---

## Comparison Table

| Aspect | Standard AccessManager | Proxy + Standard AccessManager | Proxy + CustomAccessManager |
|--------|----------------------|-------------------------------|----------------------------|
| **Public functions** | Don't use `restricted` modifier | Must whitelist each one | Public by default ✅ |
| **Restricted functions** | Use `restricted` modifier + configure | Configure in AccessManager | Configure in AccessManager ✅ |
| **Logic location** | Split (contract + manager) | Split (proxy + manager) ❌ | Centralized (manager only) ✅ |
| **Auditability** | Permissions in code + config | Permissions in proxy + config | Permissions in config only ✅ |
| **Implementation complexity** | Needs modifiers | No modifiers needed ✅ | No modifiers needed ✅ |

---

## Equivalence: CustomAccessManager = Restricted + PUBLIC_ROLE

An important insight is that the `CustomAccessManager` approach produces **exactly the same effect** as using the `restricted` modifier with `PUBLIC_ROLE` in the standard AccessManager pattern.

### Standard Pattern: Restricted + PUBLIC_ROLE

```solidity
contract Counter is AccessManaged {
    function increment() external restricted {
        // Function is controlled by AccessManager
    }
}

// In AccessManager configuration:
accessManager.setTargetFunctionRole(
    address(counter), 
    [Counter.increment.selector], 
    PUBLIC_ROLE  // Anyone can call
);
```

**Result**: Function is public (anyone can call), but it's explicitly configured in AccessManager.

### Proxy Pattern: Unconfigured in CustomAccessManager

```solidity
contract Counter {
    function increment() external {
        // No modifier, plain function
    }
}

// Using CustomAccessManager with proxy:
// - No configuration needed for increment()
// - CustomAccessManager.getTargetFunctionRole() returns PUBLIC_ROLE for unconfigured functions
```

**Result**: Function is public (anyone can call), and it's treated as intentionally unconfigured.

### Why They're Equivalent

Both approaches achieve the same end result:
- ✅ **Public access** - Anyone can call the function
- ✅ **Centralized configuration** - All access control managed through AccessManager
- ✅ **Explicit intent** - Clear distinction between public and restricted functions

The key difference is:
- **Standard pattern**: You explicitly configure it to `PUBLIC_ROLE` (opt-in configuration)
- **CustomAccessManager**: Unconfigured functions default to `PUBLIC_ROLE` (opt-out via configuration)

This equivalence validates that `CustomAccessManager` maintains the same security model and flexibility as the standard pattern, just with a more convenient default behavior for proxy-based architectures.

---

## Use Cases

### When to Use CustomAccessManager

✅ **Proxy-based access control** - When using `AccessManagedProxy` pattern  
✅ **Mixed public/restricted functions** - When you have both types of functions  
✅ **Configuration-driven permissions** - When you want all permissions in AccessManager  
✅ **Simplified implementations** - When you want implementation contracts without access control code  

### When Standard AccessManager is Better

✅ **Direct contract calls** - When not using a proxy  
✅ **All functions restricted** - When every function should be controlled  
✅ **Explicit opt-in** - When you want functions to explicitly declare they're restricted  


## Conclusion

The `CustomAccessManager` solves the fundamental problem of proxy-based access control by making **unconfigured functions public by default** while maintaining **explicit control over restricted functions**. This keeps all access control logic centralized in the AccessManager, making the system easier to understand, audit, and maintain.

By tracking which functions have been explicitly configured, we can distinguish between "intentionally public" (unconfigured) and "explicitly restricted" (configured) functions, providing the best of both worlds.

