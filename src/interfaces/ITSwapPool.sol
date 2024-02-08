// ✅

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface ITSwapPool {
    // e this is the interface for working with the TSwapPool.sol contract from the TSwap Protocol
    // qanswered why are we only using the price of a pool token in weth?
    // a we should not be, this is a bug
    function getPriceOfOnePoolTokenInWeth() external view returns (uint256);
}
