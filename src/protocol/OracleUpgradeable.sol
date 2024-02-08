// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import { ITSwapPool } from "../interfaces/ITSwapPool.sol";
import { IPoolFactory } from "../interfaces/IPoolFactory.sol";
// e this is where upgradability comes into play
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// e this is inherited in the main ThunderLoan.sol contract
contract OracleUpgradeable is Initializable {
    address private s_poolFactory;

    // e upgradeable constracts cant have constructors, because the logic is in the implementation contract, but the
    // storage is in the proxy
    // e this is why we have an initializer here

    // @audit info missing zero-address check
    function __Oracle_init(address poolFactoryAddress) internal onlyInitializing {
        __Oracle_init_unchained(poolFactoryAddress);
    }

    function __Oracle_init_unchained(address poolFactoryAddress) internal onlyInitializing {
        s_poolFactory = poolFactoryAddress;
    }

    // we are calling an external conrtact that is not in the scope. What if the price gets manipulated?
    // @audit you should use forked tests for this isntead of using a mock of the external contract
    // q what if the token has only 6 decimals?
    function getPriceInWeth(address token) public view returns (uint256) {
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);
        return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }

    // @audit info: this is redundant
    function getPrice(address token) external view returns (uint256) {
        return getPriceInWeth(token);
    }

    function getPoolFactoryAddress() external view returns (address) {
        return s_poolFactory;
    }
}
