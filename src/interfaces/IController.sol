// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Market} from "../Market.sol";
import {Vault} from "../Vault.sol";
import {Resolver} from "../Resolver.sol";
import {Position} from "../Position.sol";

/**
 * @title IController
 * @notice Defines the external interface for the Controller, the main orchestration contract.
 * @dev This interface includes definitions for EIP712 orders, administrative functions,
 * order matching, and user-facing actions like claiming.
 */
interface IController {
    //===========================================
    //                 Structs
    //===========================================

    /**
     * @notice Represents a gasless, EIP712-signed order.
     * @param user The address of the trader.
     * @param marketId The unique identifier for the market.
     * @param outcome The index of the outcome being traded.
     * @param amount The total amount of shares for this order.
     * @param price The price per share (scaled, e.g., 0-100).
     * @param nonce A unique number to prevent order replay.
     * @param expiration The Unix timestamp when the order expires.
     * @param isBuy True if the order is a buy, false if it's a sell.
     */
    struct Order {
        address user;
        bytes32 marketId;
        uint256 outcome;
        uint256 amount;
        uint256 price;
        uint256 nonce;
        uint256 expiration;
        bool isBuy;
    }

    //===========================================
    //                 Events
    //===========================================

    /// @notice Emitted when the pause state is changed.
    event ControllerPausedState(bool isPaused);
    /// @notice Emitted when fees are updated.
    event FeeChanged(uint128 newTradeFee, uint128 newClaimFee);
    /// @notice Emitted when the treasury address is changed.
    event TreasuryChanged(address indexed newTreasury);
    /// @notice Emitted when an admin's status is changed.
    event AdminChanged(address indexed admin, bool isWhitelisted);
    /// @notice Emitted when an order is successfully filled.
    event OrderFilled(
        bytes32 indexed marketId,
        bytes32 buyHash,
        bytes32 sellHash,
        uint256 filledAmount
    );
    /// @notice Emitted when an order is cancelled by its user.
    event OrderCancelled(bytes32 indexed orderHash);
    /// @notice Emitted when a user successfully claims their winnings.
    event Claimed(
        address indexed user,
        bytes32 indexed marketId,
        uint256 outcome,
        uint256 amount,
        uint256 fee
    );

    //===========================================
    //                 Errors
    //===========================================

    /// @notice Reverts if the caller is not an authorized Admin or Owner.
    error UnauthorizedCaller();
    /// @notice Reverts if contract operations are paused.
    error MarketPaused();
    /// @notice Reverts if an order's fill amount exceeds its total amount.
    error AmountOrderReached();
    /// @notice Reverts if an address parameter is address(0).
    error NonZeroAddress();
    /// @notice Reverts if a fee is set too high (e.g., > 10%).
    error FeeTooHigh();
    /// @notice Reverts if claiming from a market that is not yet resolved.
    error MarketNotResolvedYet();
    /// @notice Reverts if claiming for an outcome that did not win.
    error MismatchAnswer();
    /// @notice Reverts if the user has no balance of the winning token to claim.
    error SenderHasNotBalance();
    /// @notice Reverts if a signed order has passed its expiration time.
    error OrderExpired();
    /// @notice Reverts if an EIP712 signature is invalid or doesn't match the user.
    error InvalidSignature();
    /// @notice Reverts if the buy and sell orders are for different markets.
    error MarketIdMismatch();
    /// @notice Reverts if the buy and sell orders are for different outcomes.
    error OutcomeMismatch();
    /// @notice Reverts if both orders are 'buy' or both are 'sell'.
    error InvalidOrderPair();
    /// @notice Reverts if the buy price is lower than the sell price.
    error PriceMismatch();
    /// @notice Reverts if attempting to fill an order with zero amount.
    error ZeroFillAmount();

    //===========================================
    //              Owner Functions
    //===========================================

    function setPaused(bool _paused) external;

    function setFee(uint128 _feeTrade, uint128 _feeClaim) external;

    function setTreasury(address _treasury) external;

    function setMarket(Market _market) external;

    function setVault(Vault _vault) external;

    function setResolver(Resolver _resolver) external;

    function setPosition(Position _position) external;

    function setAdmin(address _admin, bool _whitelisted) external;

    //===========================================
    //              Admin Functions
    //===========================================

    function createMarket(
        bytes32 _marketId,
        uint256 _numberOfOutcome,
        uint256 _deadlineTime
    ) external;

    function updateDeadline(
        bytes32 _marketId,
        uint256 _deadlineTime
    ) external;

    function fillOrder(
        IController.Order calldata _buyOrder,
        bytes calldata _buySignature,
        IController.Order calldata _sellOrder,
        bytes calldata _sellSignature,
        uint256 _fillAmount
    ) external;

    function resolveManually(bytes32 _marketId, uint256 _answer) external;

    //===========================================
    //              User Functions
    //===========================================

    function cancelOrder(
        IController.Order calldata _order,
        bytes calldata _signature
    ) external;

    function claim(bytes32 _marketId, uint256 _outcome) external;

    //===========================================
    //              View Functions
    //===========================================

    function filledAmounts(bytes32 orderHash) external view returns (uint256);
}