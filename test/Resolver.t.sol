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

    /// @notice Checks in constructor input validations
    function test_constructorFails() external {
        vm.expectRevert();
        new Resolver(address(0), address(market), oracle, controller);
        vm.expectRevert();
        new Resolver(owner, address(0), oracle, controller);
        vm.expectRevert();
        new Resolver(owner, address(market), address(0), controller);
        vm.expectRevert();
        new Resolver(owner, address(market), oracle, address(0));
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

        vm.expectRevert();
        resolver.setOracle(newOracle);
        vm.expectRevert();
        resolver.setController(newController);
        vm.expectRevert();
        resolver.setPaused(true);

        vm.startPrank(owner);
        vm.expectRevert();
        resolver.setOracle(address(0));
        vm.expectRevert();
        resolver.setController(address(0));
        vm.stopPrank();

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

        vm.expectRevert();
        resolver.getAnswer(question);

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

        vm.expectRevert();
        resolver.getAnswer(question);

        vm.prank(controller);
        resolver.resolve(question, answer);

        assertEq(resolver.isResolved(question), true);
        assertEq(resolver.getAnswer(question), answer);
    }

    /// @notice Ensures the authorized controller can also resolve a market.
    function test_resolveReverts() external {
        bytes32 question = keccak256("question"); // Fixed typo here
        uint256 answer = 0;
        uint256 outcomeCount = 2;
        uint256 deadline = 1 days;

        _createMarket(question, outcomeCount, deadline);

        vm.expectRevert();
        resolver.getAnswer(question);

        vm.prank(controller);
        vm.expectRevert(); // not maturing yet
        resolver.resolve(question, answer);

        skip(2 days);

        vm.prank(controller);
        vm.expectRevert(); // answer higher than number of outcome
        resolver.resolve(question, 10);

        vm.prank(owner);
        resolver.setPaused(true);

        vm.prank(controller);
        vm.expectRevert(); // paused
        resolver.resolve(question, answer);
        
        vm.prank(owner);
        resolver.setPaused(false);

        vm.startPrank(controller);
        resolver.resolve(question, answer);

        vm.expectRevert(); // already answered
        resolver.resolve(question, answer);

        vm.stopPrank();

        assertEq(resolver.isResolved(question), true);
        assertEq(resolver.getAnswer(question), answer);
    }

    /// @notice Helper function to create a new market via the controller.
    function _createMarket(
        bytes32 _marketId,
        uint256 _outcomeCount,
        uint256 _deadlineTime
    ) internal {
        vm.prank(controller);
        market.createMarket(_marketId, _outcomeCount, _deadlineTime);
    }
}
