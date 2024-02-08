// ✅

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface IPoolFactory {
    // e this is the interface for working with the PoolFactory.sol contract from the TSwap Protocol
    function getPool(address tokenAddress) external view returns (address);
}
