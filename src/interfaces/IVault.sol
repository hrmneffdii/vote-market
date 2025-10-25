// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IVault
 * @notice Defines the external interface for the Vault contract, which manages user collateral.
 */
interface IVault {
    //===========================================
    //                 Events
    //===========================================

    /// @notice Emitted when a user deposits collateral.
    event Deposited(address indexed user, uint256 amount);
    /// @notice Emitted when a user withdraws available collateral.
    event Withdrawn(address indexed user, uint256 amount);
    /// @notice Emitted when collateral is locked for a market.
    event Locked(bytes32 indexed marketId, address indexed user, uint256 amount);
    /// @notice Emitted when collateral is released from a market.
    event Unlocked(bytes32 indexed marketId, address indexed user, uint256 amount);
    /// @notice Emitted when available collateral is transferred between users.
    event Transferred(bytes32 indexed marketId, address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when the vault is first created.
    event VaultCreated(address indexed owner, address indexed controller);
    /// @notice Emitted when the authorized Controller address is changed.
    event VaultControllerChanged(address indexed oldController, address indexed newController);
    /// @notice Emitted when the pause state is changed.
    event VaultPauseState(bool isPaused);
    /// @notice Emitted when stuck ERC20 tokens are rescued by the owner.
    event TokenRescue(IERC20 indexed token, uint256 amount);
    /// @notice Emitted when the collateral token is changed.
    event VaultTokenChanged(IERC20 indexed newToken);

    //===========================================
    //                 Errors
    //===========================================

    /// @notice Reverts if contract operations are paused.
    error VaultPaused();
    /// @notice Reverts if the caller is not the authorized Controller.
    error UnauthorizedCaller();
    /// @notice Reverts if an address parameter is address(0).
    error NonZeroAddress();
    /// @notice Reverts if a value or amount parameter is 0.
    error NonZeroAmount();
    /// @notice Reverts if a user has an insufficient available balance.
    error InsufficientAmount();
    /// @notice Reverts if a market has insufficient locked collateral.
    error InsufficientLockedAmount();

    //===========================================
    //                Functions
    //===========================================

    /**
     * @notice Deposits collateral tokens into the vault.
     * @dev Caller must first approve the vault contract to spend their tokens.
     * @param _amount The amount of collateral tokens to deposit.
     */
    function deposit(uint256 _amount) external;

    /**
     * @notice Withdraws available collateral tokens from the vault.
     * @dev Reverts if the withdrawal amount exceeds the user's available balance.
     * @param _amount The amount of collateral tokens to withdraw.
     */
    function withdraw(uint256 _amount) external;

    /**
     * @notice Locks a user's available collateral for a market position.
     * @dev Must be called by the authorized Controller contract.
     * @param _marketId The identifier for the market.
     * @param _user The user whose collateral is being locked.
     * @param _amount The amount of collateral to lock.
     */
    function lock(bytes32 _marketId, address _user, uint256 _amount) external;

    /**
     * @notice Releases collateral from a resolved market to a user's available balance.
     * @dev Must be called by the authorized Controller contract.
     * @param _marketId The identifier for the market.
     * @param _user The user receiving the released collateral.
     * @param _amount The amount of collateral to release.
     */
    function release(bytes32 _marketId, address _user, uint256 _amount) external;

    /**
     * @notice Transfers available collateral between two users internally.
     * @dev Must be called by the authorized Controller contract to settle trades efficiently.
     * @param _marketId The identifier for the market (for event logging).
     * @param _from The user sending the collateral.
     * @param _to The user receiving the collateral.
     * @param _amount The amount to transfer.
     */
    function transfer(bytes32 _marketId, address _from, address _to, uint256 _amount) external;

    /**
     * @notice Gets the available (unlocked) collateral balance of a user.
     * @param _user The address of the user to query.
     * @return The user's available balance.
     */
    function getBalance(address _user) external view returns (uint256);

    /**
     * @notice Gets the total collateral locked for a specific market.
     * @param _marketId The identifier of the market.
     * @return The total locked collateral for the market.
     */
    function getTotalLocked(bytes32 _marketId) external view returns (uint256);

    /**
     * @notice Updates the address of the authorized Controller contract.
     * @dev Can only be called by the contract owner.
     * @param _newController The address of the new Controller.
     */
    function setController(address _newController) external;

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @dev Can only be called by the contract owner.
     * @param _paused True to pause, false to unpause.
     */
    function setPaused(bool _paused) external;
}