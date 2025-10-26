// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Market} from "../src/Market.sol";

contract MarketTest is Test {
    uint256 initialOutcome = 2;
    address owner = makeAddr("owner");
    address controller = makeAddr("controller");

    Market market;

    /// @notice Sets up the Market contract before each test.
    function setUp() external {
        market = new Market(owner, controller, initialOutcome);
    }

    /// @notice Checks if the constructor state variables are set correctly.
    function test_initialize() external view {
        assertEq(market.owner(), owner);
        assertEq(market.paused(), false);
        assertEq(market.controller(), controller);
        assertEq(market.maxOutcome(), initialOutcome);
    }

    /// @notice Ensures the owner can update the controller, max outcome, and pause state.
    function test_setConfig() external {
        address newController = makeAddr("newController");
        uint256 newMaxOutcome = 3;

        vm.startPrank(owner);
        market.setController(newController);
        market.setMaxOutcome(newMaxOutcome);
        market.setPaused(true);
        vm.stopPrank();

        assertEq(market.controller(), newController);
        assertEq(market.maxOutcome(), newMaxOutcome);
        assertEq(market.paused(), true);
    }

    /// @notice Ensures market creation fails (reverts) with invalid parameters.
    function test_createMarketRevert() external {
        bytes32 question = bytes32(0);
        uint256 outcomeCount = 2;
        uint256 deadlineTime = 0;

        // 1. Reverts if marketId is bytes32(0)
        vm.prank(controller);
        vm.expectRevert();
        market.createMarket(question, outcomeCount, deadlineTime);

        question = bytes32("question");
        outcomeCount = 0; // Invalid outcome count
        deadlineTime = 0;

        // 2. Reverts if outcomeCount is less than 2
        vm.prank(controller);
        vm.expectRevert();
        market.createMarket(question, outcomeCount, deadlineTime);
    }

    /// @notice Tests the successful creation and lifecycle of a market.
    function test_createMarketSuccessfully() external {
        bytes32 question = keccak256("question");
        uint256 outcomeCount = 2;
        uint256 deadlineTime = 0;

        // 1. Create the market
        vm.prank(controller);
        market.createMarket(question, outcomeCount, deadlineTime);

        skip(1 days);

        // 2. Revert if updating deadline to a time in the past
        vm.prank(controller);
        vm.expectRevert();
        market.updateDeadlineTime(question, 1 days - 10);

        // 3. Successfully update deadline to a future time
        vm.prank(controller);
        market.updateDeadlineTime(question, 7 days);

        // 4. Check state variables
        assertEq(market.getDeadlineTime(question), 7 days);
        assertEq(market.getOutcomeCount(question), outcomeCount);
        assertEq(market.getMarketExists(question), true);

        // 5. Check maturity status after time passes
        skip(10 days); // Move time past the 7-day deadline
        assertEq(market.isMarketMature(question), true);
    }
}