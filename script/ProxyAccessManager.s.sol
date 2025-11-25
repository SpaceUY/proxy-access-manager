// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Counter} from "../src/proxy-access-manager/Counter.sol";
import {AccessManagedProxy} from "../src/proxy-access-manager/AccessManagedProxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title ProxyAccessManagerScript
 * @notice Script to deploy Counter behind AccessManagedProxy with AccessManager
 * @dev This script demonstrates the proxy-access-manager pattern where:
 *      1. AccessManager is deployed to manage permissions
 *      2. Counter implementation is deployed (with no access control logic)
 *      3. AccessManagedProxy is deployed pointing to Counter implementation
 *      4. AccessManager is configured to control permissions for proxy functions
 * 
 *      Key difference from AccessManager pattern:
 *      - Counter implementation has NO access control code - it's plain functions
 *      - Access control happens at the proxy level before calls reach the implementation
 *      - All functions are permissioned by default through the proxy
 */
contract ProxyAccessManagerScript is Script {
    Counter public counterImplementation;
    AccessManagedProxy public proxy;
    AccessManager public accessManager;

    // Define custom roles (uint64) - same as AccessManager.s.sol
    // ADMIN_ROLE = 0 is predefined in AccessManager
    // PUBLIC_ROLE = type(uint64).max is predefined in AccessManager
    uint64 public constant INCREMENTER_ROLE = 1;
    uint64 public constant SETTER_ROLE = 2;
    // We can use ADMIN_ROLE (0) for reset()

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address deployer = msg.sender;

        // 1. Deploy AccessManager with deployer as initial admin
        accessManager = new AccessManager(deployer);
        console.log("AccessManager deployed at:", address(accessManager));

        // 2. Deploy Counter implementation (no access control - plain contract)
        counterImplementation = new Counter();
        console.log("Counter implementation deployed at:", address(counterImplementation));

        // 3. Deploy AccessManagedProxy pointing to Counter implementation
        // Note: _data is empty bytes since Counter constructor has no parameters
        bytes memory initData = "";
        proxy = new AccessManagedProxy(address(counterImplementation), initData, accessManager);
        console.log("AccessManagedProxy deployed at:", address(proxy));

        // Cast proxy to Counter interface for easier interaction
        Counter counter = Counter(address(proxy));
        console.log("Counter (via proxy) address:", address(counter));

        // 4. Grant roles to the deployer (with 0 execution delay for immediate access)
        accessManager.grantRole(INCREMENTER_ROLE, deployer, 0);
        console.log("Granted INCREMENTER_ROLE to:", deployer);

        accessManager.grantRole(SETTER_ROLE, deployer, 0);
        console.log("Granted SETTER_ROLE to:", deployer);

        // 5. Configure function selectors to require specific roles
        // IMPORTANT: Configure permissions for the PROXY address, not the implementation!
        // setNumber() requires SETTER_ROLE
        bytes4[] memory setNumberSelector = new bytes4[](1);
        setNumberSelector[0] = Counter.setNumber.selector;
        accessManager.setTargetFunctionRole(address(proxy), setNumberSelector, SETTER_ROLE);
        console.log("Configured setNumber() to require SETTER_ROLE");

        // increment() requires INCREMENTER_ROLE
        bytes4[] memory incrementSelector = new bytes4[](1);
        incrementSelector[0] = Counter.increment.selector;
        accessManager.setTargetFunctionRole(address(proxy), incrementSelector, INCREMENTER_ROLE);
        console.log("Configured increment() to require INCREMENTER_ROLE");

        // reset() requires ADMIN_ROLE (0)
        bytes4[] memory resetSelector = new bytes4[](1);
        resetSelector[0] = Counter.reset.selector;
        accessManager.setTargetFunctionRole(address(proxy), resetSelector, uint64(0)); // ADMIN_ROLE = 0
        console.log("Configured reset() to require ADMIN_ROLE");

        vm.stopBroadcast();
    }
}

