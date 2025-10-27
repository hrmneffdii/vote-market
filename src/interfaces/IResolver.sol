// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IResolver
 * @notice Defines the external interface for the Resolver contract, which handles
 * the resolution of markets by recording the winning outcome.
 */
interface IResolver {
    //===========================================
    //                 Events
    //===========================================

    /// @notice Emitted when a market is successfully resolved.
    event Resolved(bytes32 indexed marketId, uint256 answer);
    /// @notice Emitted when the authorized Controller address is changed.
    event ResolverControllerChanged(address indexed oldController, address indexed newController);
    /// @notice Emitted when the authorized Oracle address is changed.
    event ResolverOracleChanged(address indexed oldOracle, address indexed newOracle);
    /// @notice Emitted when the pause state is changed.
    event ResolverPauseState(bool isPaused);

    //===========================================
    //                 Errors
    //===========================================

    /// @notice Reverts if contract operations are paused.
    error ResolverPaused();
    /// @notice Reverts if the caller is not the authorized Controller or Oracle.
    error UnauthorizedCaller();
    /// @notice Reverts if an address parameter is address(0).
    error NonZeroAddress();
    /// @notice Reverts if attempting to resolve a market that is not yet mature.
    error MarketNotMaturingYet();
    /// @notice Reverts if attempting to resolve a market that is already resolved.
    error MarketAlreadyResolved();
    /// @notice Reverts if the provided resolution outcome is invalid (e.g., out of bounds).
    error InvalidOutcome();
    /// @notice Reverts if attempting to get the resolution for an unresolved market.
    error MarketNotResolved();

    //===========================================
    //                Functions
    //===========================================

    /**
     * @notice Resolves a market by setting the winning outcome.
     * @dev Must be called by the authorized Controller or Oracle.
     * @param _marketId The unique identifier for the market.
     * @param _answer The index of the winning outcome.
     */
    function resolve(bytes32 _marketId, uint256 _answer) external;

    /**
     * @notice Updates the address of the authorized Controller.
     * @dev Can only be called by the contract owner.
     * @param _newController The address of the new Controller contract.
     */
    function setController(address _newController) external;

    /**
     * @notice Updates the address of the authorized Oracle.
     * @dev Can only be called by the contract owner.
     * @param _newOracle The address of the new Oracle.
     */
    function setOracle(address _newOracle) external;

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @dev Can only be called by the contract owner.
     * @param _paused True to pause, false to unpause.
     */
    function setPaused(bool _paused) external;

    /**
     * @notice Checks if a market has been resolved.
     * @param _marketId The identifier of the market to check.
     * @return True if the market is resolved, false otherwise.
     */
    function isResolved(bytes32 _marketId) external view returns (bool);

    /**
     * @notice Gets the winning outcome for a resolved market.
     * @dev Reverts if the market has not been resolved.
     * @param _marketId The identifier of the market.
     * @return The index of the winning outcome.
     */
    function getAnswer(bytes32 _marketId) external view returns (uint256);
}
