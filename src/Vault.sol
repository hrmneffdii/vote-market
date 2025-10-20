// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IVault} from "./interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Vault 
 * @notice Vault contract performs collateral management for the protocol.
 * @dev Manages user deposits, withdrawals, and locks/unlocks collateral
 * based on commands from an authorized Controller contract.
 */
contract Vault is IVault, Ownable {
    using SafeERC20 for IERC20;

    //===========================================
    //             State Variables             //             
    //===========================================

    /// @notice The ERC20 token contract used as collateral for all positions
    IERC20 public token;

    /// @notice Address of the authorized Controller contract permitted to manage funds (lock/unlock)
    address public controller;

    /// @notice Emergency pause status. If true, key contract operations are halted
    bool public paused;

    /// @notice Tracks the available (unlocked) collateral balance for each user
    mapping(address => uint256) private balances;

    /// @notice Tracks the total amount of collateral locked for each specific marketId
    mapping(bytes32 => uint256) private totalLockedPerMarket;

    //===========================================
    //               Modifiers                 //
    //===========================================

    modifier whenNotPaused {
        if (paused) revert VaultPaused();
        _;
    }

    modifier onlyController {
        if (_msgSender() != controller) revert UnauthorizedCaller();
        _;
    }

    //===========================================
    //              Constructor                //
    //===========================================

    /**
     * @notice Initializes the Vault contract
     * @param _owner The address of the contract owner (admin)
     * @param _controller The address of the authorized Controller contract
     */
    constructor(address _owner, address _controller) Ownable(_owner) {
        if (_owner == address(0)) revert NonZeroAddress();
        if (_controller == address(0)) revert NonZeroAddress();
        
        controller = _controller;

        emit VaultCreated(_owner, _controller);
    }

    //===========================================
    //             User Functions              //
    //===========================================
    
    /**
     * @notice Deposits ERC20 collateral tokens into the vault
     * @dev Increases the user's available balance.
     * Caller must approve the vault to spend tokens first.
     * @param amount The amount of collateral tokens to deposit
     */
    function deposit(uint256 amount) external whenNotPaused {
        if (amount == 0) revert NonZeroAmount();

        token.safeTransferFrom(_msgSender(), address(this), amount);
        balances[_msgSender()] += amount;

        emit Deposited(_msgSender(), amount);
    }

    /**
     * @notice Withdraws available ERC20 collateral tokens from the vault
     * @dev Decreases the user's available balance.
     * Reverts if the amount exceeds the user's available balance.
     * @param amount The amount of collateral tokens to withdraw
     */
    function withdraw(uint256 amount) external whenNotPaused {
        if (amount == 0) revert NonZeroAmount();
        if (balances[_msgSender()] < amount) revert InsufficientAmount();

        balances[_msgSender()] -= amount;
        token.safeTransfer(_msgSender(), amount);

        emit Withdrawn(_msgSender(), amount);
    }
    
    //===========================================
    //          Controller Functions           //
    //===========================================
    
    /**
     * @notice Locks a user's available collateral for a market position
     * @dev Called by the Controller contract
     * Moves balance from 'available' (balances) to 'locked' (totalLockedPerMarket).
     * @param marketId The identifier for the market
     * @param user The user whose collateral is being locked
     * @param amount The amount of collateral to lock
     */
    function lock(
        bytes32 marketId,
        address user,
        uint256 amount
    ) external onlyController whenNotPaused {
        if (balances[user] < amount) revert InsufficientAmount();

        balances[user] -= amount;
        totalLockedPerMarket[marketId] += amount;

        emit Locked(marketId, user, amount);
    }

    /**
     * @notice Unlocks collateral from a resolved market back to a user
     * @dev Called by the Controller contract
     * Moves balance from 'locked' (totalLockedPerMarket) to 'available' (balances).
     * @param marketId The identifier for the market
     * @param user The user receiving the unlocked collateral
     * @param amount The amount of collateral to unlock
     */
    function unlock(
        bytes32 marketId,
        address user,
        uint256 amount
    ) external onlyController whenNotPaused {
        if (totalLockedPerMarket[marketId] < amount) revert InsufficientLockedAmount();

        totalLockedPerMarket[marketId] -= amount;
        balances[user] += amount;

        emit Unlocked(marketId, user, amount);
    }

    /**
     * @notice Transfers available collateral between two users internally
     * @dev Called by the Controller contract
     * This is a gas optimization; no tokens leave the vault.
     * @param marketId The identifier for the market (for tracking)
     * @param from The user sending the collateral
     * @param to The user receiving the collateral
     * @param amount The amount to transfer
     */
    function transfer(
        bytes32 marketId,
        address from,
        address to,
        uint256 amount
    ) external onlyController whenNotPaused {
        if (balances[from] < amount) revert InsufficientAmount();
        if (to == address(0)) revert NonZeroAddress();

        balances[from] -= amount;
        balances[to] += amount;

        emit Transferred(marketId, from, to, amount);
    }
    
    //===========================================
    //              Owner Functions            //
    //===========================================
    
    /**
     * @notice Updates the address of the authorized Controller contract
     * @param _newController The address of the new controller
     */
    function setController(address _newController) external onlyOwner {
        if (_newController == address(0)) revert NonZeroAddress();

        address oldController = controller;
        controller = _newController;

        emit VaultControllerChanged(oldController, _newController);
    }

    /**
     * @notice Sets the emergency pause state of the contract
     * @param _paused True to pause, false to unpause
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;

        emit VaultPauseState(paused);
    }

    /**
     * @notice Rescues any ERC20 tokens accidentally sent to this contract
     * @param _token The address of the ERC20 token to rescue
     */
    function rescue(IERC20 _token) external onlyOwner {
        if (address(_token) == address(0)) revert NonZeroAddress();

        uint256 balance = _token.balanceOf(address(this));
        _token.safeTransfer(owner(), balance);

        emit TokenRescue(_token, balance);
    }

    //===========================================
    //               View Functions            //
    //===========================================
    
    /**
     * @notice Gets the available (unlocked) collateral balance of a user
     * @param user The address of the user
     * @return uint256 The user's available balance
     */
    function getBalance(
        address user
    ) external view returns (uint256) {
        return balances[user];
    }

    /**
     * @notice Gets the total collateral locked for a specific market
     * @param marketId The identifier of the market
     * @return uint256 The total locked collateral for that market
     */
    function getTotalLocked(
        bytes32 marketId
    ) external view returns (uint256) {
        return totalLockedPerMarket[marketId];
    }
}