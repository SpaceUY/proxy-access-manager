// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title Counter
 * @notice A simple counter contract with no access control in the implementation
 * @dev This contract demonstrates the proxy-access-manager pattern where access control
 *      is handled at the proxy level, not in the implementation. All functions are plain
 *      public/external functions with no modifiers or access checks.
 * 
 *      The AccessManagedProxy intercepts all calls before they reach this implementation
 *      and checks permissions via AccessManager. This means:
 *      - No `restricted` modifier needed
 *      - No `onlyRole` modifier needed
 *      - All access control is configured in AccessManager at deployment time
 *      - Functions are permissioned by default through the proxy
 */
contract Counter {
    uint256 public number;

    // Events
    event NumberSet(uint256 oldNumber, uint256 newNumber);
    event NumberIncremented(uint256 newNumber);
    event NumberReset(uint256 oldNumber);

    /**
     * @notice Set the number
     * @param newNumber The new number to set
     * @dev Access control is enforced by AccessManagedProxy, not this contract
     */
    function setNumber(uint256 newNumber) external {
        uint256 oldNumber = number;
        number = newNumber;
        emit NumberSet(oldNumber, newNumber);
    }

    /**
     * @notice Increment the number
     * @dev Access control is enforced by AccessManagedProxy, not this contract
     */
    function increment() external {
        number++;
        emit NumberIncremented(number);
    }

    /**
     * @notice Reset the number to zero
     * @dev Access control is enforced by AccessManagedProxy, not this contract
     */
    function reset() external {
        uint256 oldNumber = number;
        number = 0;
        emit NumberReset(oldNumber);
    }
}

