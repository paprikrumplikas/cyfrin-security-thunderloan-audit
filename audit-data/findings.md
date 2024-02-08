### [H-1] Erroneus `ThunderLoan::updateExchangeRate` in the `depost` function causes protocol to think is has collected more fees than it actually does, which blocks redemption and incorrectly sets the exchange rate

**Description:** In the `ThunderLoan` system, the `echangeRate` is responsible for calculating the exchange rate between assetTokens and underlying tokens. In a way, it is responsible it is resposible for keeping track how many fees to give to liquidity providers. 

However, the `deposit` function updates this rate without collecting any fees!

```javascript
    function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);
        // @audit high
@>      uint256 calculatedFee = getCalculatedFee(token, amount);
@>      assetToken.updateExchangeRate(calculatedFee);
        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

**Impact:** There are several impacts to this bug:

1. The `redeem` function is blocked, becsuase the protocol thinks the owed tokens is more than it has on its balance.
2. Rewards are incorrecly calculated, leading to liquidity providers getting way more or less than deserved.

**Proof of Concept:** Consider the following scenario:

1. LP deposits.
2. User takes out a flash loan.
3. It is now impossible to redeem.


Insert the following piece of code in `ThunderLoanTest.t.sol`:

<details>
<summary>Proof of Code</summary>

```javascript

    function test_redeemAfterLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
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

        // @note fails!
        // initial deposit: 1000e18
        // fee: 3e17
        // balance: 1000.3e18
        // reqd to transfer back: 1003.3e18
    }
```
</details>


**Recommended Mitigation:** Remove the incorrectly update exchange lines from `deposit` as follows:

```diff
    function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);
        // @audit high
-       uint256 calculatedFee = getCalculatedFee(token, amount);
-       assetToken.updateExchangeRate(calculatedFee);
        token.safeTransferFrom(msg.sender, address(assetToken), amount);
```
