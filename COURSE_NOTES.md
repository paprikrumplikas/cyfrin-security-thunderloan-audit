# Tools

1. upgradehub.xyz: Shows the upgrade history of smart contract, how they changed over time.


# Tricks

1. Use `Ctrl + Shift + F` to search on the right, in all the files / directories.
2. generate a pdf from the findings (need Pandoc and LaTex install, and the eisvogel.latex template installed, and pdf viewer as a add-on installed)
https://github.com/Cyfrin/security-and-auditing-full-course-s23/discussions/31

```javascript 
cd audit-data
pandoc report.md -o 2024-02-13-ThunderLoan-audit-report.pdf --from markdown --template=eisvogel --listings
```
3. We can use forge to inspect the storage layout of a contract, e.g.
   `forge inspect ThunderLoan storage`
4. Compare 2 files like this:
   `diff ./src/protocol/ThunderLoan.sol ./src/upgradedProtocol/ThunderLoanUpgraded.sol`
   If we already modified one of the files, added comments, etc, then:
   1. `git checkout -b demo` (this is where we will save and commit our modifications)
   2. `git brach` (should be on demo, if not, swtich)
   3. `git status`
   4. `git add .`
   5. `git commit -m "commit message`
   6. `git switch main`
   7. `git pull`
   8. then do the diff


# Learnings

1. Generally, if interface A imports interface B, and then contract C imports IF A, then contract C will have access to IF B too.
However, this is not the case when we are using a named import in contract C as `import {interfaceA} from "./InterfaceA.sol`. In this case, contract C wont have access to IF B.
2. Upgradeable constracts cant have constructors, because the logic is in the implementation contract, but the storage is in the proxy. We cant have strorage in the implementation contract too.
3. If a protocol depends on some external contracts, one should write forked tests to check whether interactions with the external contracts are fine. Using mocked contracts for testing interactions with external contracts is not good enough.
4. @note `SafeERC20` is a wrapper library around ERC20 operations for ERC20s that do weird stuff. Helps e.g. transfers with weird ERC20s.
5. We can use forge to inspect the storage layout of a contract, e.g.
   `forge inspect ThunderLoan storage`
6. When a contract is compiled, Solidity allocates storage slots for state variables in the order they are declared in the contract. This storage layout must remain consistent across different versions of an implementation contract in an upgradable contract system. If the layout changes (e.g., by adding, removing, or changing the type of state variables), it can lead to mismatches between the expected location of data in storage and the actual data, potentially resulting in loss of data or unpredictable behavior.
7. When it comes to upgrading an upgradeable contract, anybody can upgrade it unless the following line is included in the contract `function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }`


# Audit

1. Solidity Metrics Report: right click on `src`, and select Solidity Metrics. On the opened tab, right click and select save in the contextual menu.
2. Slither:
   1. use `make slither`: it uses the `slither.config.json` file to config the run to exclude unnecessary stuff



# Risks, bugs, attack vectors

1. Centralization
2. Failiure to initialize: if an upgradeable contract has an initilaizer, it could be frontrun after deployment, somebody else could call it. Mitigation: 
   - call the initializer() function rigth from the deploy script, or
   - use some modifiers that block interactions with the rest of the contract until it is initialized (costs gas).
3. Rewards manipulation
4. Oracle manipulation (!!! VERY COMMON ISSUE !!!): using DEX reserves as an oracle is a horrible idea. They can get manipulated so easily!
5. Storage slot collision (e.g. when upgrading contracts)
