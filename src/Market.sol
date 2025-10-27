// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IMarket} from "./interfaces/IMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Market
 * @notice A registry contract that stores and manages the core properties of prediction markets.
 * @dev This contract is responsible for creating markets and storing their essential data,
 * such as the number of outcomes and resolution deadlines. All state-changing actions
 * related to market management are restricted to an authorized Controller contract.
 */
contract Market is IMarket, Ownable {
    //===========================================
    //             State Variables
    //===========================================

    /// @notice The authorized Controller contract permitted to create and manage markets.
    address public controller;

    /// @notice Emergency pause status. If true, market creation and updates are halted.
    bool public paused;

    /// @notice The maximum number of outcomes a market can have.
    uint256 public maxOutcome;

    /// @notice Mapping from market ID to the number of possible outcomes.
    mapping(bytes32 => uint256) private outcomeCounts;

    /// @notice Mapping from market ID to a boolean indicating if it has been created.
    mapping(bytes32 => bool) private marketExists;

    /// @notice Mapping from market ID to its resolution deadline timestamp.
    mapping(bytes32 => uint256) private deadlines;

    //===========================================
    //               Modifiers
    //===========================================

    modifier whenNotPaused() {
        // Menggunakan error yang lebih spesifik untuk kontrak ini
        if (paused) revert MarketPaused();
        _;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert UnauthorizedCaller();
        _;
    }

    //===========================================
    //              Constructor
    //===========================================

    /**
     * @notice Initializes the Market contract.
     * @param _initialOwner The address of the contract owner (admin).
     * @param _initialController The address of the authorized Controller contract.
     * @param _maxOutcome The maximum outcome count
     */
    constructor(address _initialOwner, address _initialController, uint256 _maxOutcome) Ownable(_initialOwner) {
        if (_initialOwner == address(0)) revert NonZeroAddress();
        if (_initialController == address(0)) revert NonZeroAddress();

        controller = _initialController;
        maxOutcome = _maxOutcome;
    }

    //===========================================
    //          Controller Functions
    //===========================================

    /**
     * @notice Creates a new market with specified parameters.
     * @dev Called only by the Controller. Stores market properties on-chain. Reverts if market already exists.
     * @param _marketId The unique identifier for the new market.
     * @param _outcomeCount The number of possible outcomes for the market (must be at least 2).
     * @param _deadlineTime The Unix timestamp for the market's resolution deadline.
     */
    function createMarket(bytes32 _marketId, uint256 _outcomeCount, uint256 _deadlineTime)
        external
        onlyController
        whenNotPaused
    {
        if (_marketId == bytes32(0)) revert NonZeroMarketId();
        if (marketExists[_marketId]) revert MarketAlreadyExists();

        if (_outcomeCount < 2 || (maxOutcome > 0 && _outcomeCount > maxOutcome)) {
            revert InvalidOutcome();
        }
        if (_deadlineTime != 0 && _deadlineTime < block.timestamp) {
            revert InvalidDate();
        }

        marketExists[_marketId] = true;
        outcomeCounts[_marketId] = _outcomeCount;
        deadlines[_marketId] = _deadlineTime;

        emit MarketCreated(_marketId, _outcomeCount, _deadlineTime);
    }

    /**
     * @notice Updates the resolution deadline for an existing market.
     * @dev Called only by the Controller. Can be used to extend or change a market's end time.
     * @param _marketId The identifier of the market to update.
     * @param _newDeadlineTime The new Unix timestamp for the deadline.
     */
    function updateDeadlineTime(bytes32 _marketId, uint256 _newDeadlineTime) external onlyController whenNotPaused {
        if (!marketExists[_marketId]) revert MarketNotExists();
        if (_newDeadlineTime != 0 && _newDeadlineTime < block.timestamp) {
            revert InvalidDate();
        }

        uint256 oldDeadline = deadlines[_marketId];
        deadlines[_marketId] = _newDeadlineTime;

        emit DeadlineUpdated(_marketId, oldDeadline, _newDeadlineTime);
    }

    //===========================================
    //              Owner Functions
    //===========================================

    /**
     * @notice Updates the address of the authorized Controller contract.
     * @param _newController The address of the new Controller.
     */
    function setController(address _newController) external onlyOwner {
        if (_newController == address(0)) revert NonZeroAddress();

        address oldController = controller;
        controller = _newController;

        emit MarketControllerChanged(oldController, _newController);
    }

    /**
     * @notice Updates the maximum allowed number of outcomes for new markets.
     * @dev Allows the owner to configure market creation constraints.
     * @param _newMaxOutcome The new maximum outcome count.
     */
    function setMaxOutcome(uint256 _newMaxOutcome) external onlyOwner {
        // Sebuah pasar membutuhkan setidaknya dua hasil
        if (_newMaxOutcome < 2) revert InvalidOutcome();

        maxOutcome = _newMaxOutcome;
    }

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @param _paused True to pause, false to unpause.
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;

        emit MarketPauseState(_paused);
    }

    //===========================================
    //               View Functions
    //===========================================

    /**
     * @notice Checks if a market's deadline has passed and it can be resolved.
     * @dev A market is considered mature if its deadline is non-zero and in the past.
     * A market with a deadline of 0 is considered mature immediately.
     * @param _marketId The identifier of the market to check.
     * @return A boolean indicating if the market is mature (true) or not (false).
     */
    function isMarketMature(bytes32 _marketId) external view override returns (bool) {
        if (!marketExists[_marketId]) revert MarketNotExists();

        uint256 currentDeadline = deadlines[_marketId];
        // Deadline 0 berarti dapat diselesaikan kapan saja.
        // Jika tidak, timestamp saat ini harus sudah melewati deadline.
        return currentDeadline == 0 || block.timestamp >= currentDeadline;
    }

    /**
     * @notice Gets the resolution deadline for a specific market.
     * @param _marketId The identifier of the market.
     * @return The Unix timestamp of the market's deadline.
     */
    function getDeadlineTime(bytes32 _marketId) external view override returns (uint256) {
        return deadlines[_marketId];
    }

    /**
     * @notice Gets the number of possible outcomes for a specific market.
     * @param _marketId The identifier of the market.
     * @return The number of outcomes.
     */
    function getOutcomeCount(bytes32 _marketId) external view override returns (uint256) {
        return outcomeCounts[_marketId];
    }

    /**
     * @notice Checks if a market with a given ID has been created.
     * @param _marketId The identifier of the market.
     * @return A boolean indicating if the market exists (true) or not (false).
     */
    function getMarketExists(bytes32 _marketId) external view override returns (bool) {
        return marketExists[_marketId];
    }
}
