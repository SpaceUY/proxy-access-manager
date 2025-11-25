// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

/**
 * @title AccessManagedProxy
 * @notice Proxy contract that intercepts all calls and checks permissions via AccessManager
 * @dev This proxy follows the "permissioned by default" pattern discussed in:
 *      https://forum.openzeppelin.com/t/accessmanagedproxy-is-a-good-idea/41917
 * 
 *      Key benefits:
 *      - All functions are permissioned by default without needing modifiers in the implementation
 *      - Access control is configured at deployment via AccessManager, not in code
 *      - Implementation contracts can be simpler with no access control logic
 *      - Easier to audit: permissions are configured in AccessManager, not scattered in code
 */
contract AccessManagedProxy is ERC1967Proxy {
    IAccessManager public immutable ACCESS_MANAGER;

    constructor(address implementation, bytes memory _data, IAccessManager manager) payable ERC1967Proxy(implementation, _data) {
        ACCESS_MANAGER = manager;
    }

    /**
     * @dev Checks with the ACCESS_MANAGER if msg.sender is authorized to call the current call's function,
     * and if so, delegates the current call to `implementation`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     * 
     * @param implementation The implementation contract address to delegate calls to
     */
    function _delegate(address implementation) internal virtual override {
        (bool immediate, ) = ACCESS_MANAGER.canCall(msg.sender, address(this), bytes4(msg.data[0:4]));
        if (!immediate) revert IAccessManaged.AccessManagedUnauthorized(msg.sender);
        super._delegate(implementation);
    }
}