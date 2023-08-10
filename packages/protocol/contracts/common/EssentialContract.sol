// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import { IAddressManager } from "./AddressManager.sol";
import { OwnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from
    "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { AddressResolver } from "./AddressResolver.sol";

/**
 * This contract serves as the base contract for many core components.
 * @title EssentialContract
 */
abstract contract EssentialContract is
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    AddressResolver
{
    /**
     * Sets a new AddressManager address.
     * @param newAddressManager Address of the new AddressManager.
     */
    function setAddressManager(address newAddressManager) external onlyOwner {
        if (newAddressManager == address(0)) revert RESOLVER_INVALID_ADDR();
        _addressManager = IAddressManager(newAddressManager);
        emit AddressManagerChanged(newAddressManager);
    }

    /**
     * Initializes the contract with an address manager.
     * @param _addressManager  The address of the address manager.
     */
    function _init(address _addressManager) internal virtual override {
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init();
        AddressResolver._init(_addressManager);
    }
}
