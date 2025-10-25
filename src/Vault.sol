// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IVault} from "./interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Vault
 * @notice Manages collateral for the protocol, handling deposits, withdrawals, and fund locking.
 * @dev This contract holds all user collateral. Fund movements (lock, release, transfer)
 * are controlled exclusively by an authorized Controller contract to ensure security.
 */
contract Vault is IVault, Ownable {
    using SafeERC20 for IERC20;

    //===========================================
    //             State Variables
    //===========================================

    /// @notice The ERC20 token used as collateral for all positions.
    IERC20 public token;

    /// @notice The authorized Controller contract permitted to manage funds (lock/release/transfer).
    address public controller;

    /// @notice Emergency pause status. If true, most operations are halted.
    bool public paused;

    /// @notice Tracks the available (unlocked) collateral balance for each user.
    mapping(address => uint256) private balances;

    /// @notice Tracks the total amount of collateral locked for each market.
    mapping(bytes32 => uint256) private totalLockedPerMarket;

    //===========================================
    //               Modifiers
    //===========================================

    modifier whenNotPaused() {
        if (paused) revert VaultPaused();
        _;
    }

    modifier onlyController() {
        if (msg.sender!= controller) revert UnauthorizedCaller();
        _;
    }

    //===========================================
    //              Constructor
    //===========================================

    /**
     * @notice Initializes the Vault contract.
     * @param _owner The address of the contract owner (admin).
     * @param _controller The address of the authorized Controller contract.
     */
    constructor(address _owner, address _controller) Ownable(_owner) {
        if (_owner == address(0)) revert NonZeroAddress();
        if (_controller == address(0)) revert NonZeroAddress();
        
        controller = _controller;

        emit VaultCreated(_owner, _controller);
    }

    //===========================================
    //             User Functions
    //===========================================
    
    /**
     * @notice Deposits collateral tokens into the vault.
     * @dev Increases the user's available balance. Caller must approve the vault to spend tokens first.
     * @param _amount The amount of collateral tokens to deposit.
     */
    function deposit(uint256 _amount) external whenNotPaused {
        if (_amount == 0) revert NonZeroAmount();

        token.safeTransferFrom(msg.sender, address(this), _amount);
        balances[msg.sender] += _amount;

        emit Deposited(msg.sender, _amount);
    }

    /**
     * @notice Withdraws available collateral tokens from the vault.
     * @dev Decreases the user's available balance. Reverts if the amount exceeds the available balance.
     * @param _amount The amount of collateral tokens to withdraw.
     */
    function withdraw(uint256 _amount) external whenNotPaused {
        if (_amount == 0) revert NonZeroAmount();
        if (balances[msg.sender] < _amount) revert InsufficientAmount();

        balances[msg.sender] -= _amount;
        token.safeTransfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _amount);
    }
    
    //===========================================
    //          Controller Functions
    //===========================================
    
    /**
     * @notice Locks a user's available collateral for a market position.
     * @dev Called only by the Controller. Moves balance from 'available' to a 'locked' state.
     * @param _marketId The identifier for the market.
     * @param _user The user whose collateral is being locked.
     * @param _amount The amount of collateral to lock.
     */
    function lock(
        bytes32 _marketId,
        address _user,
        uint256 _amount
    ) external onlyController whenNotPaused {
        if (balances[_user] < _amount) revert InsufficientAmount();

        balances[_user] -= _amount;
        totalLockedPerMarket[_marketId] += _amount;

        emit Locked(_marketId, _user, _amount);
    }

    /**
     * @notice Releases collateral from a resolved market back to a user's available balance.
     * @dev Called only by the Controller. Moves balance from a 'locked' to 'available' state.
     * @param _marketId The identifier for the market.
     * @param _user The user receiving the released collateral.
     * @param _amount The amount of collateral to release.
     */
    function release(
        bytes32 _marketId,
        address _user,
        uint256 _amount
    ) external onlyController whenNotPaused {
        if (totalLockedPerMarket[_marketId] < _amount) revert InsufficientLockedAmount();

        totalLockedPerMarket[_marketId] -= _amount;
        balances[_user] += _amount;

        emit Unlocked(_marketId, _user, _amount);
    }

    /**
     * @notice Transfers available collateral between two users internally.
     * @dev Called only by the Controller. A gas-efficient way to settle trades, as no actual token transfer occurs.
     * @param _marketId The identifier for the market (for event logging).
     * @param _from The user sending the collateral.
     * @param _to The user receiving the collateral.
     * @param _amount The amount to transfer.
     */
    function transfer(
        bytes32 _marketId,
        address _from,
        address _to,
        uint256 _amount
    ) external onlyController whenNotPaused {
        if (balances[_from] < _amount) revert InsufficientAmount();
        if (_to == address(0)) revert NonZeroAddress();

        balances[_from] -= _amount;
        balances[_to] += _amount;

        emit Transferred(_marketId, _from, _to, _amount);
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

        emit VaultControllerChanged(oldController, _newController);
    }

    /**
     * @notice Updates the collateral token contract address.
     * @dev Should only be called during initial setup. Changing this on a live vault is highly discouraged.
     * @param _token The address of the new ERC20 collateral token.
     */
    function setToken(IERC20 _token) external onlyOwner {
        if (address(_token) == address(0)) revert NonZeroAddress();
            
        token = _token;

        emit VaultTokenChanged(token);
    }

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @param _paused True to pause, false to unpause.
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;

        emit VaultPauseState(_paused);
    }

    /**
     * @notice Rescues ERC20 tokens accidentally sent to this contract.
     * @dev This function cannot be used to rescue the main collateral token (`token`).
     * @param _token The address of the ERC20 token to rescue.
     */
    function rescue(IERC20 _token) external onlyOwner {
        if (address(_token) == address(0)) revert NonZeroAddress();
        if (address(_token) == address(token)) revert(); // Cannot rescue collateral token

        uint256 balance = _token.balanceOf(address(this));
        _token.safeTransfer(owner(), balance);

        emit TokenRescue(_token, balance);
    }

    //===========================================
    //               View Functions
    //===========================================
    
    /**
     * @notice Gets the available (unlocked) collateral balance of a user.
     * @param _user The address of the user.
     * @return The user's available balance.
     */
    function getBalance(
        address _user
    ) external view returns (uint256) {
        return balances[_user];
    }

    /**
     * @notice Gets the total collateral locked for a specific market.
     * @param _marketId The identifier of the market.
     * @return The total locked collateral for that market.
     */
    function getTotalLocked(
        bytes32 _marketId
    ) external view returns (uint256) {
        return totalLockedPerMarket[_marketId];
    }
}