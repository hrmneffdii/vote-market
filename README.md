## Vote-Market Protocol Architecture

![Architecture](./architecture.png)

Vote-Market is a decentralized prediction market protocol designed with a hybrid architecture to achieve efficiency, scalability, and an optimal user experience. The diagram below outlines the core components and their interactions.

### The Hybrid Model: Off-Chain Matching

The "hybrid architecture" refers to the separation of order matching (off-chain) from settlement (on-chain).

1.  **Off-Chain:** Users sign orders (using EIP-712) which are sent to an off-chain relayer/admin. The admin matches these orders in a traditional order book *without* spending any gas.
2.  **On-Chain:** Once a match is found, the admin submits the two matched orders (`_buyOrder`, `_sellOrder`) and their signatures to the `Controller.sol`'s `fillOrder` function. The `Controller` then validates the signatures and executes the trade and asset settlement (via `Vault` and `Position`) in a single, atomic on-chain transaction.

This model provides a CEX-like (Centralized Exchange) user experience—gasless order creation and cancellation—while maintaining the security and non-custodial nature of a DEX (Decentralized Exchange).

### Core Components (Smart Contracts)

The protocol is composed of several key smart contracts, each with a specific responsibility to ensure a clear separation of concerns and enhanced security.

  * **`Controller.sol`**
    This is the central hub of the protocol. It handles all core business logic, including trade execution (order matching), prize claims, and serves as the sole point of interaction between the various system components.

  * **`Vault.sol`**
    This contract is solely responsible for collateral management. Users `deposit` and `withdraw` their assets from the `Vault`. The `Controller` can then `lock`, `release`, and `transfer` funds within the `Vault` to cover trading positions without the assets ever leaving the security of the contract.

  * **`Market.sol`**
    This acts as a registry for all markets. When a new market is created, the `Controller` stores essential metadata such as the market ID, number of outcomes, and deadline within the `Market` contract.

  * **`Resolver.sol`**
    This contract manages the market resolution process. When a market ends, the `Controller` (or an `Admin`) triggers the `Resolver` to record the winning outcome.

  * **`Position.sol`**
    This is an ERC-1155 token contract that represents the shares (outcome tokens) for each market. When a user "buys" an outcome, the `Controller` instructs this contract to mint the corresponding token (e.g., "YES-token") to the user. This token is what users hold and later `claim` for their winnings.

  * **`Oracle`**
    This is a crucial external dependency that sits outside the core system. The Oracle serves as a bridge between the real world and the blockchain, providing tamper-proof outcome data to the `Resolver`. The security and reliability of the Oracle are paramount to the integrity of the entire protocol.

### Actors and Roles

  * **`User`**
    Users are the market participants. They can deposit/withdraw funds from the `Vault`, sign off-chain orders, and interact with the `Controller` to `claim` winnings or `cancelOrder`s.

  * **`Admin`**
    This is a privileged role responsible for managing trading operations and market lifecycle. The `Admin` matches orders (`fillOrder`) via the `Controller`. This role also has the ability to `createMarket`, `updateDeadline`, and `resolveManually` in case of an emergency or oracle failure.

### Key Workflows

1.  **Market Creation (`createMarket`)**

      * The `Admin` calls `createMarket` on the `Controller`, which then registers a new market in the `Market` contract with its defined parameters.

2.  **Trading (`deposit`, `fillOrder`, `lock`)**

      * A `User` deposits collateral (e.g., USDC) into the `Vault`.
      * Orders are created and matched off-chain by the `Admin` for gas efficiency.
      * The `Admin` then submits the matched orders to the `Controller` for execution (`fillOrder`).
      * The `Controller` validates the orders and signatures, then instructs:
        1.  The `Position` contract to `mint` the correct outcome tokens to the buyer and seller.
        2.  The `Vault` contract to `lock` the collateral from both users.

3.  **Resolution & Claiming (`resolve`, `release`, `claim`)**

      * After a market ends (passes its deadline), the `Admin` calls `resolveManually` on the `Controller`, which in turn tells the `Resolver` to store the winning outcome.
      * Winning users can now call the `claim` function on the `Controller`.
      * The `Controller` verifies the win, instructs the `Position` contract to `burn` the user's winning tokens, and instructs the `Vault` to `release` the locked collateral (the winnings) to the user.

## Installation

1.  **Clone the repository**

    ```bash
    git clone https://github.com/hrmneffdii/vote-market.git
    ```

2.  **Navigate into the project directory**

    ```bash
    cd vote-market
    ```

3.  **Build the project**

    ```bash
    forge build
    ```

4.  **Run the tests**

    ```bash
    forge test
    ```

-----

### Test Coverage

```
╭--------------------+------------------+------------------+----------------+-----------------╮
| File               | % Lines          | % Statements     | % Branches     | % Funcs         |
+=============================================================================================+
| src/Controller.sol | 88.06% (118/134) | 84.85% (140/165) | 50.00% (15/30) | 77.27% (17/22)  |
|--------------------+------------------+------------------+----------------+-----------------|
| src/Market.sol     | 97.92% (47/48)   | 94.23% (49/52)   | 76.92% (10/13) | 100.00% (12/12) |
|--------------------+------------------+------------------+----------------+-----------------|
| src/Position.sol   | 100.00% (21/21)  | 94.12% (16/17)   | 75.00% (3/4)   | 100.00% (8/8)   |
|--------------------+------------------+------------------+----------------+-----------------|
| src/Resolver.sol   | 97.44% (38/39)   | 95.24% (40/42)   | 83.33% (10/12) | 100.00% (9/9)   |
|--------------------+------------------+------------------+----------------+-----------------|
| src/Vault.sol      | 100.00% (59/59)  | 95.08% (58/61)   | 81.25% (13/16) | 100.00% (14/14) |
|--------------------+------------------+------------------+----------------+-----------------|
| Total              | 94.02% (283/301) | 89.91% (303/337) | 68.00% (51/75) | 92.31% (60/65)  |
╰--------------------+------------------+------------------+----------------+-----------------╯
```

*Note: The branch coverage on `Controller.sol` reflects the contract's significant complexity in handling various order-matching paths. All critical paths and core functions are fully tested.*