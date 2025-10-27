// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Vault} from "../src/Vault.sol";

contract VaultTest is Test {
    ERC20Mock USDC;
    Vault vault;

    address controller = makeAddr("controller");
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 1_000e6;

    /// @notice Sets up the initial state for each test case.
    function setUp() external {
        vm.startPrank(owner);
        vault = new Vault(owner, controller);
        USDC = new ERC20Mock();

        // Set the collateral token (USDC)
        vault.setToken(USDC);

        // Give initial balances to Alice and Bob
        USDC.mint(alice, INITIAL_BALANCE);
        USDC.mint(bob, INITIAL_BALANCE);
        vm.stopPrank();
    }

    function test_constructorFails() external {
        vm.expectRevert();
        new Vault(address(0), controller);

        vm.expectRevert();
        new Vault(owner, address(0));
    }

    /// @notice Checks if the constructor state variables are set correctly.
    function test_initializeState() external view {
        assertEq(vault.owner(), owner, "Incorrect owner");
        assertEq(vault.controller(), controller, "Incorect controlloer");
        assertEq(vault.paused(), false, "Vault should not be paused");
    }

    /// @notice Ensures the owner can change configurations (controller, token, pause).
    function test_setConfig() external {
        address newController = makeAddr("newController");
        ERC20Mock newToken = new ERC20Mock();

        vm.expectRevert();
        vault.setController(newController);

        vm.expectRevert();
        vault.setToken(newToken);

        vm.startPrank(owner);
        vm.expectRevert();
        vault.setController(address(0));

        vm.expectRevert();
        vault.setToken(ERC20Mock(address(0)));
        vm.stopPrank();

        vm.startPrank(owner);
        vault.setController(newController);
        vault.setToken(newToken);
        vault.setPaused(true);
        vm.stopPrank();

        assertEq(vault.controller(), newController, "Incorrect controller");
        assertEq(address(vault.token()), address(newToken), "Incorrect token");
        assertEq(vault.paused(), true, "Vault should be paused");
    }

    /// @notice Ensures a user (Alice) can deposit tokens.
    function test_deposit() external {
        vm.startPrank(alice);
        USDC.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE);
        vm.stopPrank();

        assertEq(vault.getBalance(alice), INITIAL_BALANCE);
        assertEq(USDC.balanceOf(address(vault)), INITIAL_BALANCE);
    }

    /// @notice Ensures depositing a zero amount will fail (revert).
    function test_depositRevert() external {
        vm.prank(alice);
        vm.expectRevert(); // Expecting a revert
        vault.deposit(0);

        vm.prank(owner);
        vault.setPaused(true);

        vm.startPrank(alice);
        USDC.approve(address(vault), INITIAL_BALANCE);

        vm.expectRevert(); // paused
        vault.deposit(INITIAL_BALANCE);
        vm.stopPrank();
    }

    /// @notice Ensures a user (Alice) can withdraw their balance.
    function test_withdraw() external {
        _deposit(alice, INITIAL_BALANCE); // Helper for deposit

        vm.prank(alice);
        vault.withdraw(INITIAL_BALANCE);

        assertEq(vault.getBalance(alice), 0);
        assertEq(USDC.balanceOf(address(vault)), 0);
        assertEq(USDC.balanceOf(alice), INITIAL_BALANCE);
    }

    /// @notice Ensures withdraw fails if the amount is 0 or exceeds the balance.
    function test_withdrawRevert() external {
        _deposit(alice, INITIAL_BALANCE);

        vm.startPrank(alice);

        // 1. Fails if amount is 0
        vm.expectRevert();
        vault.withdraw(0);

        // 2. Fails if amount > balance
        vm.expectRevert();
        vault.withdraw(INITIAL_BALANCE + 1);
        vm.stopPrank();

        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(alice);
        vm.expectRevert(); // paused
        vault.withdraw(INITIAL_BALANCE);
    }

    /// @notice Ensures the controller can lock a user's balance (making it non-withdrawable).
    function test_lock() external {
        bytes32 marketId = keccak256("question1");
        _deposit(alice, INITIAL_BALANCE);

        vm.expectRevert(); // unauthorize caller
        vault.lock(marketId, alice, INITIAL_BALANCE);

        // Controller locks Alice's funds
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(controller);
        vm.expectRevert(); // paused
        vault.lock(marketId, alice, INITIAL_BALANCE);

        vm.prank(owner);
        vault.setPaused(false);

        vm.prank(controller);
        vault.lock(marketId, alice, INITIAL_BALANCE);

        // Alice tries to withdraw locked funds (must fail)
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(INITIAL_BALANCE);

        assertEq(vault.getBalance(alice), 0); // Free balance = 0
        assertEq(vault.getTotalLocked(marketId), INITIAL_BALANCE); // Locked balance = initial
        assertEq(USDC.balanceOf(address(vault)), INITIAL_BALANCE); // Token stays in vault
    }

    /// @notice Ensures the controller can release a locked balance (making it withdrawable).
    function test_release() external {
        bytes32 marketId = keccak256("question1");
        _deposit(alice, INITIAL_BALANCE);

        // 1. Lock funds
        vm.prank(controller);
        vault.lock(marketId, alice, INITIAL_BALANCE);

        vm.expectRevert(); // unauthorize caller
        vault.release(marketId, alice, INITIAL_BALANCE);

        // Controller locks Alice's funds
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(controller);
        vm.expectRevert(); // paused
        vault.release(marketId, alice, INITIAL_BALANCE);

        vm.prank(owner);
        vault.setPaused(false);

        // 2. Release funds
        vm.prank(controller);
        vm.expectRevert(); // unauthorize caller
        vault.release(marketId, alice, INITIAL_BALANCE + 1);

        // 2. Release funds
        vm.prank(controller);
        vault.release(marketId, alice, INITIAL_BALANCE);

        // 3. Alice withdraws the released funds
        vm.prank(alice);
        vault.withdraw(INITIAL_BALANCE);

        assertEq(vault.getBalance(alice), 0);
        assertEq(USDC.balanceOf(alice), INITIAL_BALANCE);
        assertEq(USDC.balanceOf(address(vault)), 0);
    }

    /// @notice Ensures the controller can transfer balances between users inside the vault.
    function test_transfer() external {
        bytes32 marketId = keccak256("question1");
        _deposit(alice, INITIAL_BALANCE);

        // Controller transfers Alice's funds to Bob (e.g., Bob won the market)
        vm.expectRevert(); // unauthorized
        vault.transfer(marketId, alice, bob, INITIAL_BALANCE);

        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(controller);
        vm.expectRevert(); // paused
        vault.transfer(marketId, alice, bob, INITIAL_BALANCE);

        vm.prank(owner);
        vault.setPaused(false);

        // 1.revert in case balance < amount
        vm.startPrank(controller);
        vm.expectRevert();
        vault.transfer(marketId, alice, bob, INITIAL_BALANCE + 1);

        // 2.revert in address from is zero
        vm.expectRevert();
        vault.transfer(marketId, address(0), bob, INITIAL_BALANCE);

        // 3.revert in address to is zero
        vm.expectRevert();
        vault.transfer(marketId, alice, address(0), INITIAL_BALANCE);

        vault.transfer(marketId, alice, bob, INITIAL_BALANCE);
        vm.stopPrank();

        assertEq(vault.getBalance(alice), 0); // Alice's balance is 0
        assertEq(vault.getBalance(bob), INITIAL_BALANCE); // Bob's balance increased
        assertEq(USDC.balanceOf(address(vault)), INITIAL_BALANCE); // Token stays in vault

        // Bob withdraws his balance
        vm.prank(bob);
        vault.withdraw(INITIAL_BALANCE);
        assertEq(vault.getBalance(bob), 0);
        assertEq(USDC.balanceOf(bob), 2 * INITIAL_BALANCE); // Initial balance + winnings
        assertEq(USDC.balanceOf(address(vault)), 0);
    }

    /// @notice Ensures the owner can rescue other (ERC20) tokens sent by mistake.
    function test_rescue() external {
        ERC20Mock anotherToken = new ERC20Mock(); // A different token (not USDC)
        anotherToken.mint(owner, INITIAL_BALANCE);

        // Owner accidentally transfers the other token to the vault
        vm.prank(owner);
        anotherToken.transfer(address(vault), INITIAL_BALANCE);
        assertEq(anotherToken.balanceOf(address(vault)), INITIAL_BALANCE);
        assertEq(anotherToken.balanceOf(owner), 0);

        vm.expectRevert(); // unauthorized caller
        vault.rescue(USDC);

        // Owner rescues the token
        vm.startPrank(owner);

        // revert in case token is usdc
        vm.expectRevert();
        vault.rescue(USDC);

        vm.expectRevert();
        vault.rescue(ERC20Mock(address(0)));

        vault.rescue(anotherToken);
        vm.stopPrank();
        assertEq(anotherToken.balanceOf(address(vault)), 0);
        assertEq(anotherToken.balanceOf(owner), INITIAL_BALANCE);
    }

    // ===================================
    //         Helper Functions
    // ===================================

    /// @notice Internal helper function to simplify the deposit process in other tests.
    function _deposit(address _actor, uint256 _amount) internal {
        vm.startPrank(_actor);
        USDC.approve(address(vault), _amount);
        vault.deposit(_amount);
        vm.stopPrank();
    }
}
