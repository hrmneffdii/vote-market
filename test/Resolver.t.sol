// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Market} from "../src/Market.sol";
import {Resolver} from "../src/Resolver.sol";

contract ResolverTest is Test {
    Market market;
    Resolver resolver;

    uint256 initialOutcome = 2;
    address owner = makeAddr("owner");
    address oracle = makeAddr("oracle");
    address controller = makeAddr("controller");

    /// @notice Sets up the Market and Resolver contracts before each test.
    function setUp() external {
        market = new Market(owner, controller, initialOutcome);
        resolver = new Resolver(owner, address(market), oracle, controller);
    }

    /// @notice Checks if the constructor state variables are set correctly.
    function test_initialize() external view {
        assertEq(resolver.oracle(), oracle);
        assertEq(resolver.paused(), false);
        assertEq(address(resolver.market()), address(market));
        assertEq(resolver.controller(), controller);
    }

    /// @notice Ensures the owner can update the oracle, controller, and pause state.
    function test_setConfig() external {
        address newOracle = makeAddr("newOracle");
        address newController = makeAddr("newController");

        vm.startPrank(owner);
        resolver.setOracle(newOracle);
        resolver.setController(newController);
        resolver.setPaused(true);
        vm.stopPrank();

        assertEq(resolver.oracle(), newOracle);
        assertEq(resolver.controller(), newController);
        assertEq(resolver.paused(), true);
    }

    /// @notice Ensures the authorized oracle can resolve a market.
    function test_oracleCanSolve() external {
        bytes32 question = keccak256("question");
        uint256 answer = 0;
        uint256 outcomeCount = 2;
        uint256 deadline = 0;

        _createMarket(question, outcomeCount, deadline);

        vm.prank(oracle);
        resolver.resolve(question, answer);

        assertEq(resolver.isResolved(question), true);
        assertEq(resolver.getAnswer(question), answer);
    }

    /// @notice Ensures the authorized controller can also resolve a market.
    function test_controllerCanSolve() external {
        bytes32 question = keccak256("question"); // Fixed typo here
        uint256 answer = 0;
        uint256 outcomeCount = 2;
        uint256 deadline = 0;

        _createMarket(question, outcomeCount, deadline);

        vm.prank(controller);
        resolver.resolve(question, answer);

        assertEq(resolver.isResolved(question), true);
        assertEq(resolver.getAnswer(question), answer);
    }

    /// @notice Helper function to create a new market via the controller.
    function _createMarket(
        bytes32 _question,
        uint256 _outcomeCount,
        uint256 _deadlineTime
    ) internal {
        vm.prank(controller);
        market.createMarket(_question, _outcomeCount, _deadlineTime);
    }
}