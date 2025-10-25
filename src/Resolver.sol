// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IResolver} from "./interfaces/IResolver.sol";
import {IMarket} from "./interfaces/IMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Resolver
 * @notice This contract is responsible for resolving prediction markets
 * by recording the winning outcome.
 * @dev This contract relies on an authorized Oracle or Controller to submit
 * the final answer. It reads market data (like maturity status) from the Market Contract.
 */
contract Resolver is IResolver, Ownable {
    //===========================================
    //             State Variables
    //===========================================

    /// @notice The Market registry contract, used to check market maturity status.
    IMarket public immutable market;

    /// @notice The authorized Controller contract address.
    address public controller;

    /// @notice The authorized Oracle address.
    address public oracle;

    /// @notice Emergency pause status. If true, new market resolutions are halted.
    bool public paused;

    /// @notice Mapping from market ID to the winning outcome.
    mapping(bytes32 => uint256) private marketIdToAnswers;

    /// @notice Mapping from market ID to a boolean indicating if the market has been resolved.
    mapping(bytes32 => bool) private isMarketIdAnswered;

    //===========================================
    //               Modifiers
    //===========================================

    modifier onlyControllerOrOracle() {
        if (msg.sender != controller && msg.sender != oracle)
            revert UnauthorizedCaller();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ResolverPaused();
        _;
    }

    //===========================================
    //              Constructor
    //===========================================

    /**
     * @notice Initializes the Resolver contract.
     * @param _initialOwner The address of the contract owner (admin).
     * @param _market The address of the Market registry contract.
     * @param _initialOracle The address of the authorized Oracle.
     * @param _initialController The address of the authorized Controller.
     */
    constructor(
        address _initialOwner,
        address _market,
        address _initialOracle,
        address _initialController
    ) Ownable(_initialOwner) {
        // Non-zero address checks, matching Market.sol style
        if (_initialOwner == address(0)) revert NonZeroAddress();
        if (_market == address(0)) revert NonZeroAddress();
        if (_initialOracle == address(0)) revert NonZeroAddress();
        if (_initialController == address(0)) revert NonZeroAddress();

        market = IMarket(_market);
        oracle = _initialOracle;
        controller = _initialController;
    }

    //===========================================
    //          Resolution Functions
    //===========================================

    /**
     * @notice Resolves a market by setting the winning outcome.
     * @dev Can only be called by the Oracle or Controller, and only after the market is mature.
     * Will revert if the market is already resolved or the outcome is invalid.
     * @param _marketId The unique identifier for the market.
     * @param _answer The index of the winning outcome.
     */
    function resolve(
        bytes32 _marketId,
        uint256 _answer
    ) external override onlyControllerOrOracle whenNotPaused {
        // 1. Check if the market is mature (fetches data from Market.sol)
        if (!market.isMarketMature(_marketId)) revert MarketNotMaturingYet();

        // 2. Check if the market has already been resolved
        if (isMarketIdAnswered[_marketId]) revert MarketAlreadyResolved();

        // 3. Check if the answer (outcome) is valid
        uint256 outcomeCount = market.getOutcomeCount(_marketId);
        if (_answer >= outcomeCount) revert InvalidOutcome();

        marketIdToAnswers[_marketId] = _answer;
        isMarketIdAnswered[_marketId] = true;

        emit Resolved(_marketId, _answer);
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

        emit ResolverControllerChanged(oldController, _newController);
    }

    /**
     * @notice Updates the address of the authorized Oracle.
     * @param _newOracle The address of the new Oracle.
     */
    function setOracle(address _newOracle) external onlyOwner {
        if (_newOracle == address(0)) revert NonZeroAddress();

        address oldOracle = oracle;
        oracle = _newOracle;

        emit ResolverOracleChanged(oldOracle, _newOracle);
    }

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @param _paused True to pause, false to unpause.
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit ResolverPauseState(_paused);
    }

    //===========================================
    //               View Functions
    //===========================================

    /**
     * @notice Checks if a market has been resolved.
     * @param _marketId The identifier of the market.
     * @return A boolean indicating if the market is resolved (true) or not (false).
     */
    function isResolved(
        bytes32 _marketId
    ) external view override returns (bool) {
        return isMarketIdAnswered[_marketId];
    }

    /**
     * @notice Gets the winning outcome for a resolved market.
     * @dev Will revert if the market has not been resolved yet.
     * @param _marketId The identifier of the market.
     * @return uint256 The index of the winning outcome.
     */
    function getAnswer(bytes32 _marketId) external view returns (uint256) {
        if (!isMarketIdAnswered[_marketId]) revert MarketNotResolved();
        return marketIdToAnswers[_marketId];
    }
}