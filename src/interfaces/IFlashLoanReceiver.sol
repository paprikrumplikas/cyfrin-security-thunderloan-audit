// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

// @audit info: unused import:
// e: ThunderLoan.sol does import IFlasLoanReceiver.sol, but with a named import specifying only that one, so
// IThunderLoan is not included
// e. IThunderLoan does actually get imported in one of the mock files. However, it is bad practice to edit live code
// for tests/mocks, we MUST remove the import from MockFlashLoanReceiver.sol".
import { IThunderLoan } from "./IThunderLoan.sol";

/**
 * @dev Inspired by Aave:
 * https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol
 */
interface IFlashLoanReceiver {
    // @audit info: missing natspec
    // qanswered is the token the token that is being borrowed?: yes
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool);
}
