// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVault} from "./interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title Vault 
 * @notice Vault contract performs collateral management 
 */
contract Vault is IVault, Ownable {
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

    modifier whenNotPaused {
        require(!paused, "Vault is paused");
        _;
    }

    modifier onlyController {
        require(msg.sender == controller, UnauthorizedCaller());
        _;
    }


    ////////////////////////////////////////////
    //////////////// CONSTRUCTOR ///////////////
    ////////////////////////////////////////////

    constructor(address _owner, address _controller) Ownable(_owner){
        require(_owner != address(0), NonZeroAddress());
        require(_controller != address(0), NonZeroAddress());
        
        controller = _controller;

        emit VaultIsCreated(_owner, _controller);
    }

    ////////////////////////////////////////////
    ////////////// USER FUNCTION ///////////////
    ////////////////////////////////////////////
    
    function deposit(uint256 amount) external whenNotPaused {}

    function withdraw(uint256 amount) external whenNotPaused {}
    
    ////////////////////////////////////////////
    /////////// CONTROLLER FUNCTION ////////////
    ////////////////////////////////////////////
    
    function lock(
        bytes32 marketId,
        address user,
        uint256 amount
    ) external onlyController whenNotPaused {}

    function unlock(
        bytes32 marketId,
        address user,
        uint256 amount
    ) external onlyController whenNotPaused {}

    function transfer(
        bytes32 marketId,
        address from,
        address to,
        uint256 amount
    ) external onlyController whenNotPaused {}
    
    ////////////////////////////////////////////
    ///////////// OWNER FUNCTION ///////////////
    ////////////////////////////////////////////
    
    function setController(address _newController) external onlyOwner {
        require(_newController != address(0));

        address oldController = controller;
        controller = _newController;

        emit VaultControllerChanged(oldController, _newController);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;

        emit VaultPauseState(paused);
    }

    ////////////////////////////////////////////
    ////////////// VIEW FUNCTION ///////////////
    ////////////////////////////////////////////
    
    function getBalance(
        address user
    ) external view returns (uint256) {
        return balances[user];
    }

    function getTotalLocked(
        bytes32 marketId
    ) external view returns (uint256) {
        return totalLockedPerMarket[marketId];
    }

}