// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// @audit the IThunderLoan interface should be implemented by the ThunderLoan.sol contract. This IF is supposed to guide
// ppl to not forget a function. So it should be imported and inherited by ThunderLoan.sol.
interface IThunderLoan {
    // @audit low/informational: this repay() function has different params than the repay() in ThunderLoan.sol
    function repay(address token, uint256 amount) external;
}
