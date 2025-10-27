// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IMarket
 * @notice Defines the external interface for the Market contract, which manages market metadata and lifecycle.
 */
interface IMarket {
    //===========================================
    //                 Events
    //===========================================

    /// @notice Emitted when a new market is created.
    event MarketCreated(bytes32 indexed marketId, uint256 outcomeCount, uint256 deadlineTime);
    /// @notice Emitted when a market's resolution deadline is updated.
    event DeadlineUpdated(bytes32 indexed marketId, uint256 oldDeadline, uint256 newDeadline);
    /// @notice Emitted when the authorized Controller address is changed.
    event MarketControllerChanged(address indexed oldController, address indexed newController);
    /// @notice Emitted when the pause state is changed.
    event MarketPauseState(bool isPaused);

    //===========================================
    //                 Errors
    //===========================================

    /// @notice Reverts if contract operations are paused.
    error MarketPaused();
    /// @notice Reverts if the caller is not the authorized Controller.
    error UnauthorizedCaller();
    /// @notice Reverts if an address parameter is address(0).
    error NonZeroAddress();
    /// @notice Reverts if a market ID parameter is bytes32(0).
    error NonZeroMarketId();
    /// @notice Reverts if the outcome count is invalid.
    error InvalidOutcome();
    /// @notice Reverts if a timestamp parameter is in the past.
    error InvalidDate();
    /// @notice Reverts if a market does not exist.
    error MarketNotExists();
    /// @notice Reverts if attempting to create a market that already exists.
    error MarketAlreadyExists();

    //===========================================
    //                Functions
    //===========================================

    /**
     * @notice Creates a new prediction market.
     * @dev Must be called by the authorized Controller. Reverts if the market ID already exists.
     * @param _marketId The unique identifier for the market.
     * @param _outcomeCount The number of possible outcomes (e.g., 2 for Yes/No).
     * @param _deadlineTime The Unix timestamp when the market closes for trading.
     */
    function createMarket(bytes32 _marketId, uint256 _outcomeCount, uint256 _deadlineTime) external;

    /**
     * @notice Updates the resolution deadline for an existing market.
     * @dev Must be called by the authorized Controller.
     * @param _marketId The identifier of the market to update.
     * @param _newDeadlineTime The new Unix timestamp for the deadline.
     */
    function updateDeadlineTime(bytes32 _marketId, uint256 _newDeadlineTime) external;

    /**
     * @notice Updates the address of the authorized Controller.
     * @dev Can only be called by the contract owner.
     * @param _newController The address of the new Controller contract.
     */
    function setController(address _newController) external;

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @dev Can only be called by the contract owner.
     * @param _paused True to pause, false to unpause.
     */
    function setPaused(bool _paused) external;

    /**
     * @notice Checks if a market has passed its deadline and is ready for resolution.
     * @dev A market is mature if its deadline has passed or if its deadline is 0.
     * @param _marketId The identifier of the market to check.
     * @return True if the market is mature, false otherwise.
     */
    function isMarketMature(bytes32 _marketId) external view returns (bool);

    /**
     * @notice Retrieves the deadline timestamp for a market.
     * @param _marketId The identifier of the market.
     * @return The Unix timestamp of the market's deadline.
     */
    function getDeadlineTime(bytes32 _marketId) external view returns (uint256);

    /**
     * @notice Retrieves the number of outcomes for a specific market.
     * @param _marketId The identifier of the market.
     * @return The total count of possible outcomes.
     */
    function getOutcomeCount(bytes32 _marketId) external view returns (uint256);

    /**
     * @notice Checks if a market with the given ID has been created.
     * @param _marketId The identifier of the market to check.
     * @return True if the market exists, false otherwise.
     */
    function getMarketExists(bytes32 _marketId) external view returns (bool);
}
