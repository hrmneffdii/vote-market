// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IVault
 * @notice Interface for vault management 
 */
interface IVault {
    /// @notice Emitted when user deposits collateral to their account
    event Deposited(address indexed user, uint256 amount);

    /// @notice Emitted when user withdraws available collateral
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when collateral is locked for a specific condition
    event Locked(bytes32 indexed marketId, address indexed user, uint256 amount);

    /// @notice Emitted when collateral is unlocked from a resolved condition
    event Unlocked(bytes32 indexed marketId, address indexed user, uint256 amount);
    
    /// @notice Emitted when collateral is transferred between users during token swaps
    event Transferred(bytes32 indexed marketId, address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when pause state is changed
    event VaultPauseState(bool paused);

    /// @notice Emitted when controller is changed
    event VaultControllerChanged(address newController, address oldController);

    /// @notice Emitted when contract is created
    event VaultIsCreated(address owner, address controller);

    /// @notice Error for zero address
    error NonZeroAddress();
    
    /// @notice Error for zero amount
    error NonZeroAmount();

    /// @notice Error for unauthorize caller
    error UnauthorizedCaller();

    /**
     * @notice Deposits ERC20 collateral tokens into user's available balance
     * @param amount Number of collateral tokens to deposit
     * @dev Requires prior ERC20 approval for vault contract
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Withdraws available collateral tokens to user's wallet
     * @param amount Number of tokens to withdraw
     * @dev Only withdraws from unlocked balance, reverts on insufficient funds
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Locks user's available collateral for position token minting
     * @param marketId Market condition identifier
     * @param user Address whose collateral to lock
     * @param amount Collateral amount to lock
     * @dev Called by MarketController contract during position creation
     */
    function lock(bytes32 marketId, address user, uint256 amount) external;

    /**
     * @notice Unlocks collateral from resolved condition to user's available balance
     * @param marketId Resolved condition identifier
     * @param user User redeeming position tokens
     * @param amount Payout amount determined by market resolution
     * @dev Called by MarketController contract after successful claim verification
     */
    function unlock(bytes32 marketId, address user, uint256 amount) external;

    /**
     * @notice Transfers collateral between users' vault balances (for token swaps)
     * @param marketId Market condition identifier for tracking
     * @param from User sending collateral
     * @param to User receiving collateral
     * @param amount Amount to transfer
     * @dev Called by MarketController during token swap settlements
     */
    function transfer(bytes32 marketId, address from, address to, uint256 amount) external;

    /**
     * @notice Returns user's available collateral balance
     * @param user Address to query
     * @return Available balance for withdrawal or position creation
     */
    function getBalance(address user) external view returns (uint256);

    /**
     * @notice Returns total locked collateral for specific condition
     * @param marketId Condition identifier
     * @return Total locked amount across all participants
     */
    function getTotalLocked(bytes32 marketId) external view returns (uint256);

    /**
     * @notice Updates authorized MarketController contract address
     * @param _contract New authorized contract address
     * @dev Only callable by contract owner
     */
    function setController(address _contract) external;

    /**
     * @notice Sets contract pause state for emergency situations
     * @param _paused Pause state boolean
     * @dev Only callable by contract owner, affects user-facing operations
     */
    function setPaused(bool _paused) external;
}