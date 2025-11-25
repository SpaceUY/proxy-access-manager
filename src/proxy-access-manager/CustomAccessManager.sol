// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title CustomAccessManager
 * @notice Custom AccessManager that can distinguish between unconfigured functions and explicitly configured functions
 * @dev Tracks which (target, selector) pairs have been explicitly configured via setTargetFunctionRole
 */
contract CustomAccessManager is AccessManager {
    // Track which (target, selector) pairs have been explicitly configured
    // Key: keccak256(abi.encodePacked(target, selector))
    mapping(bytes32 => bool) private _configuredSelectors;

    constructor(address initialAdmin) AccessManager(initialAdmin) {}

    /**
     * @notice Check if a (target, selector) has been explicitly configured
     * @param target The target contract address
     * @param selector The function selector
     * @return configured True if the selector has been configured via setTargetFunctionRole
     */
    function isSelectorConfigured(address target, bytes4 selector) public view returns (bool configured) {
        bytes32 key = keccak256(abi.encodePacked(target, selector));
        return _configuredSelectors[key];
    }

    /**
     * @notice Override getTargetFunctionRole to return PUBLIC_ROLE for unconfigured functions
     * @dev This makes unconfigured functions public by default (accessible by anyone when target is open)
     *      Configured functions return their explicitly set role
     * 
     *      IMPORTANT: This returns the role required when the target is OPEN.
     *      If the target is closed (via setTargetClosed), canCall() will block ALL calls
     *      regardless of what role this function returns. The closed state is checked
     *      before getTargetFunctionRole() is called in canCall().
     * 
     * @param target The target contract address
     * @param selector The function selector
     * @return roleId The role ID required to call this function (PUBLIC_ROLE if unconfigured, when target is open)
     */
    function getTargetFunctionRole(address target, bytes4 selector) 
        public 
        view 
        virtual 
        override 
        returns (uint64 roleId) 
    {
        // Check if this selector has been explicitly configured
        bool isConfigured = isSelectorConfigured(target, selector);
        
        // If not configured, return PUBLIC_ROLE (anyone can call when target is open)
        // Note: If target is closed, canCall() blocks everything regardless of role
        if (!isConfigured) {
            return PUBLIC_ROLE;
        }
        
        // If configured, return the configured role from parent
        return super.getTargetFunctionRole(target, selector);
    }

    /**
     * @notice Override setTargetFunctionRole to track configured selectors
     * @dev This allows us to distinguish between unconfigured (returns PUBLIC_ROLE) and explicitly set roles
     * 
     *      IMPORTANT: Setting a function to PUBLIC_ROLE effectively "unsets" it - it becomes unconfigured
     *      and will be treated the same as if it was never configured (public by default).
     */
    function setTargetFunctionRole(
        address target,
        bytes4[] calldata selectors,
        uint64 roleId
    ) public virtual override onlyAuthorized {
        // Call parent to set the role
        super.setTargetFunctionRole(target, selectors, roleId);
        
        // Handle configuration tracking
        for (uint256 i = 0; i < selectors.length; ++i) {
            bytes32 key = keccak256(abi.encodePacked(target, selectors[i]));
            
            if (roleId == PUBLIC_ROLE) {
                // Setting to PUBLIC_ROLE effectively "unsets" the configuration
                // Mark as unconfigured (or remove from configured mapping)
                _configuredSelectors[key] = false;
            } else {
                // Mark as configured for any other role
                _configuredSelectors[key] = true;
            }
        }
    }
}

