# Tools

1. upgradehub.xyz: Shows the upgrade history of smart contract, how they changed over time.


# Tricks

1. Use `Ctrl + Shift + F` to search on the right, in all the files / directories.


# Learnings

1. Generally, if interface A imports interface B, and then contract C imports IF A, then contract C will have access to IF B too.
However, this is not the case when we are using a named import in contract C as `import {interfaceA} from "./InterfaceA.sol`. In this case, contract C wont have access to IF B.
2. Upgradeable constracts cant have constructors, because the logic is in the implementation contract, but the storage is in the proxy. We cant have strorage in the implementation contract too.
3. If a protocol depends on some external contracts, one should write do forked tests to check whether interactions with the external contracts are fine. Using mocked contracts for testing interactions with external contracts is not good enough.
4. @note `SafeERC20` is a wrapper library around ERC20 operations for ERC20s that do weird stuff. Helps e.g. transfers with weierd ERC20s.


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
4. Oracle manipulation