// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Market} from "./Market.sol";
import {Vault} from "./Vault.sol";
import {Resolver} from "./Resolver.sol";
import {Position} from "./Position.sol";
import {IController} from "./interfaces/IController.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Controller
 * @notice This is the main orchestration contract for the prediction market.
 * @dev It connects all other contracts (Market, Vault, Resolver, Position)
 * and handles the core logic for order matching (EIP712), market creation,
 * and claiming winnings. It operates with two main roles: Owner and Admin.
 */
contract Controller is IController, EIP712, Ownable {
    using ECDSA for bytes32;

    //===========================================
    //             State Variables
    //===========================================

    /// @notice The EIP712 typehash for the gasless Order struct.
    bytes32 private constant ORDER_TYPEHASH =
        keccak256(
            "Order(address user,bytes32 marketId,uint256 outcome,uint256 amount,uint256 price,uint256 nonce,uint256 expiration,bool isBuy)"
        );

    /// @notice Emergency pause status. If true, trading and claiming are halted.
    bool public paused;

    /// @notice Basis points constant (10000 = 100%).
    uint256 private constant BPS = 10_000;

    /// @notice The trading fee in basis points (e.g., 50 = 0.5%).
    uint128 public feeTrade;

    /// @notice The fee for claiming winnings in basis points (e.g., 100 = 1.0%).
    uint128 public feeClaim;

    /// @notice The address where fees are collected.
    address public treasury;

    /// @notice The Vault contract instance, handling collateral (ERC20).
    Vault public vault;

    /// @notice The Market registry contract instance, storing market metadata.
    Market public market;

    /// @notice The Resolver contract instance, handling market resolution.
    Resolver public resolver;

    /// @notice The Position token contract instance (ERC1155).
    Position public position;

    /// @notice Mapping of whitelisted admin addresses (matchers/relayers).
    mapping(address => bool) public whitelistedAdmin;

    /// @notice Mapping from order hash to the amount that has been filled.
    mapping(bytes32 => uint256) public filledAmounts;

    //===========================================
    //               Modifiers
    //===========================================

    modifier onlyAdmin() {
        if (!whitelistedAdmin[msg.sender]) revert UnauthorizedCaller();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert MarketPaused();
        _;
    }

    //===========================================
    //              Constructor
    //===========================================

    /**
     * @notice Initializes the Controller contract and its dependencies.
     * @param _initialOwner The address of the contract owner (super admin).
     * @param _treasury The address for fee collection.
     * @param _market The deployed Market contract address.
     * @param _vault The deployed Vault contract address.
     * @param _resolver The deployed Resolver contract address.
     * @param _position The deployed Position (ERC1155) contract address.
     */
    constructor(
        address _initialOwner,
        address _treasury,
        Market _market,
        Vault _vault,
        Resolver _resolver,
        Position _position
    ) Ownable(_initialOwner) EIP712("Controller", "1") {
        if (_initialOwner == address(0)) revert NonZeroAddress();
        if (_treasury == address(0)) revert NonZeroAddress();
        if (address(_market) == address(0)) revert NonZeroAddress();
        if (address(_vault) == address(0)) revert NonZeroAddress();
        if (address(_resolver) == address(0)) revert NonZeroAddress();
        if (address(_position) == address(0)) revert NonZeroAddress();

        treasury = _treasury;
        market = _market;
        vault = _vault;
        resolver = _resolver;
        position = _position;
    }

    //===========================================
    //              Owner Functions
    //===========================================

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @param _paused True to pause, false to unpause.
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit ControllerPausedState(_paused); // Assumes event in IController
    }

    /**
     * @notice Sets the trade and claim fees.
     * @dev Fees are in basis points. 1000 = 10%.
     * @param _feeTrade The new trading fee.
     * @param _feeClaim The new claiming fee.
     */
    function setFee(uint128 _feeTrade, uint128 _feeClaim) external onlyOwner {
        // Max fee 10%
        if (_feeTrade > 1000 || _feeClaim > 1000) revert FeeTooHigh();

        feeTrade = _feeTrade;
        feeClaim = _feeClaim;
        emit FeeChanged(_feeTrade, _feeClaim); // Assumes event in IController
    }

    /**
     * @notice Updates the treasury address.
     * @dev Can be set to address(0) to disable fee collection.
     * @param _treasury The new treasury address.
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit TreasuryChanged(_treasury); // Assumes event in IController
    }

    /**
     * @notice Updates the Market contract address.
     * @param _market The new Market contract address.
     */
    function setMarket(Market _market) external onlyOwner {
        if (address(_market) == address(0)) revert NonZeroAddress();
        market = _market;
    }

    /**
     * @notice Updates the Vault contract address.
     * @param _vault The new Vault contract address.
     */
    function setVault(Vault _vault) external onlyOwner {
        if (address(_vault) == address(0)) revert NonZeroAddress();
        vault = _vault;
    }

    /**
     * @notice Updates the Resolver contract address.
     * @param _resolver The new Resolver contract address.
     */
    function setResolver(Resolver _resolver) external onlyOwner {
        if (address(_resolver) == address(0)) revert NonZeroAddress();
        resolver = _resolver;
    }

    /**
     * @notice Updates the Position contract address.
     * @param _position The new Position contract address.
     */
    function setPosition(Position _position) external onlyOwner {
        if (address(_position) == address(0)) revert NonZeroAddress();
        position = _position;
    }

    /**
     * @notice Grants or revokes admin privileges for an address.
     * @param _admin The address to modify.
     * @param _whitelisted True to grant, false to revoke.
     */
    function setAdmin(address _admin, bool _whitelisted) external onlyOwner {
        whitelistedAdmin[_admin] = _whitelisted;
        emit AdminChanged(_admin, _whitelisted); // Assumes event in IController
    }

    //===========================================
    //              Admin Functions
    //===========================================

    /**
     * @notice Creates a new market via the Market contract.
     * @dev Called only by an Admin.
     * @param _marketId The unique identifier for the market.
     * @param _numberOfOutcome The number of possible outcomes.
     * @param _deadlineTime The market's resolution deadline.
     */
    function createMarket(
        bytes32 _marketId,
        uint256 _numberOfOutcome,
        uint256 _deadlineTime
    ) external onlyAdmin {
        market.createMarket(_marketId, _numberOfOutcome, _deadlineTime);
    }

    /**
     * @notice Updates the deadline for an existing market.
     * @dev Called only by an Admin.
     * @param _marketId The identifier of the market to update.
     * @param _deadlineTime The new Unix timestamp for the deadline.
     */
    function updateDeadline(
        bytes32 _marketId,
        uint256 _deadlineTime
    ) external onlyAdmin {
        market.updateDeadlineTime(_marketId, _deadlineTime);
    }

    /**
     * @notice Fills two matching signed orders (buy and sell).
     * @dev This is the core matching function, called by an Admin (relayer).
     * It verifies signatures, checks order validity, and executes the trade.
     * @param _buyOrder The buyer's signed Order struct.
     * @param _buySignature The buyer's EIP712 signature.
     * @param _sellOrder The seller's signed Order struct.
     * @param _sellSignature The seller's EIP712 signature.
     * @param _fillAmount The amount of shares to trade.
     */
    function fillOrder(
        IController.Order calldata _buyOrder,
        bytes calldata _buySignature,
        IController.Order calldata _sellOrder,
        bytes calldata _sellSignature,
        uint256 _fillAmount
    ) external onlyAdmin whenNotPaused {
        // --- 1. Checks ---
        if (_buyOrder.marketId != _sellOrder.marketId) revert MarketIdMismatch();
        if (_buyOrder.outcome != _sellOrder.outcome) revert OutcomeMismatch();
        if (!_buyOrder.isBuy || _sellOrder.isBuy) revert InvalidOrderPair();
        if (_buyOrder.price < _sellOrder.price) revert PriceMismatch();
        if (_fillAmount == 0) revert ZeroFillAmount();

        bytes32 buyHash = _verifyOrder(_buyOrder, _buySignature);
        bytes32 sellHash = _verifyOrder(_sellOrder, _sellSignature);

        if (filledAmounts[buyHash] + _fillAmount > _buyOrder.amount)
            revert AmountOrderReached();
        if (filledAmounts[sellHash] + _fillAmount > _sellOrder.amount)
            revert AmountOrderReached();

        // --- 2. Effects ---
        filledAmounts[buyHash] += _fillAmount;
        filledAmounts[sellHash] += _fillAmount;

        // --- 3. Interactions ---
        uint256 tokenId = position.getTokenId(
            _buyOrder.marketId,
            _buyOrder.outcome
        );
        uint256 balanceOfSeller = position.balanceOf(_sellOrder.user, tokenId);

        if (balanceOfSeller >= _fillAmount) {
            _swapToken(_buyOrder, _sellOrder, tokenId, _fillAmount);
        } else {
            // This case handles minting a full set for the seller
            _mintToken(_buyOrder, _sellOrder, tokenId, _fillAmount);
        }

        uint256 priceForBuyer = _fillAmount * _buyOrder.price;
        uint256 priceForSeller = _fillAmount * _sellOrder.price;

        // Lock collateral from both users in the Vault
        vault.lock(_buyOrder.marketId, _buyOrder.user, priceForBuyer);
        vault.lock(_sellOrder.marketId, _sellOrder.user, priceForSeller);

        if (feeTrade > 0 && treasury != address(0)) {
            _takesFee(_buyOrder, _sellOrder, priceForBuyer, priceForSeller);
        }

        emit OrderFilled(_buyOrder.marketId, buyHash, sellHash, _fillAmount); // Assumes event
    }

    /**
     * @notice Manually resolves a market via the Resolver contract.
     * @dev Called only by an Admin.
     * @param _marketId The identifier of the market to resolve.
     * @param _answer The winning outcome index.
     */
    function resolveManually(
        bytes32 _marketId,
        uint256 _answer
    ) external onlyAdmin whenNotPaused {
        resolver.resolve(_marketId, _answer);
    }

    //===========================================
    //          User Functions (External)
    //===========================================

    /**
     * @notice Allows a user to cancel their own signed order.
     * @dev This works by setting the order's filledAmount to its total amount,
     * preventing it from being filled by an admin.
     * @param _order The Order struct to cancel.
     * @param _signature The EIP712 signature for the order.
     */
    function cancelOrder(
        IController.Order calldata _order,
        bytes calldata _signature
    ) external {
        if (_order.user != msg.sender) revert UnauthorizedCaller();

        bytes32 orderHash = _verifyOrder(_order, _signature);

        // Set filled amount to max to effectively cancel it
        filledAmounts[orderHash] = _order.amount;
        emit OrderCancelled(orderHash); // Assumes event
    }

    /**
     * @notice Allows a user to claim their winnings from a resolved market.
     * @dev The user burns their winning outcome tokens and in exchange,
     * the Vault releases their locked collateral (1 token = 1 collateral).
     * @param _marketId The market to claim from.
     * @param _outcome The outcome index the user is claiming for.
     */
    function claim(bytes32 _marketId, uint256 _outcome) external whenNotPaused {
        if (!resolver.isResolved(_marketId)) revert MarketNotResolvedYet();

        uint256 answer = resolver.getAnswer(_marketId);
        if (answer != _outcome) revert MismatchAnswer();

        uint256 tokenId = position.getTokenId(_marketId, _outcome);
        uint256 balance = position.balanceOf(msg.sender, tokenId);

        if (balance == 0) revert SenderHasNotBalance();

        uint256 fee = (balance * feeClaim) / BPS;

        // Release the full balance from lock
        vault.release(_marketId, msg.sender, balance);

        if (fee > 0 && treasury != address(0)) {
            // Transfer the fee portion to the treasury
            vault.transfer(_marketId, msg.sender, treasury, fee);
        }

        // Burn the user's winning tokens
        position.burn(msg.sender, tokenId, balance);

        emit Claimed(msg.sender, _marketId, _outcome, balance, fee); // Assumes event
    }

    //===========================================
    //         Internal & Private Functions
    //===========================================

    /**
     * @notice Internal function to take trade fees from both parties.
     */
    function _takesFee(
        IController.Order calldata _buyOrder,
        IController.Order calldata _sellOrder,
        uint256 priceForBuyer,
        uint256 priceForSeller
    ) internal {
        uint256 feeFromBuyer = (priceForBuyer * feeTrade) / BPS;
        uint256 feeFromSeller = (priceForSeller * feeTrade) / BPS;

        vault.transfer(
            _buyOrder.marketId,
            _buyOrder.user,
            treasury,
            feeFromBuyer
        );

        vault.transfer(
            _sellOrder.marketId,
            _sellOrder.user,
            treasury,
            feeFromSeller
        );
    }

    /**
     * @notice Verifies an EIP712 signed order.
     * @dev Checks expiration, hashes the typed data, and recovers the signer.
     * @param order The Order struct.
     * @param signature The EIP712 signature.
     * @return orderHash The hash of the verified order.
     */
    function _verifyOrder(
        IController.Order calldata order,
        bytes calldata signature
    ) internal view returns (bytes32) {
        if (block.timestamp > order.expiration) revert OrderExpired();

        bytes32 orderHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order.user,
                    order.marketId,
                    order.outcome,
                    order.amount,
                    order.price,
                    order.nonce,
                    order.expiration,
                    order.isBuy
                )
            )
        );

        address signer = orderHash.recover(signature);
        if (signer != order.user) revert InvalidSignature();

        return orderHash;
    }

    /**
     * @notice Internal function to swap tokens when the seller already has them.
     * @dev Burns seller's tokens and mints them for the buyer.
     */
    function _swapToken(
        IController.Order calldata _buyOrder,
        IController.Order calldata _sellOrder,
        uint256 _tokenId,
        uint256 _fillAmount
    ) internal {
        // 1. Burn seller's token
        position.burn(_sellOrder.user, _tokenId, _fillAmount);

        // 2. Mint buyer's token
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = _tokenId;
        amounts[0] = _fillAmount;
        position.mintBatch(_buyOrder.user, ids, amounts);
    }

    /**
     * @notice Internal function to mint a full set of tokens.
     * @dev Mints the specified outcome token for the buyer.
     * Mints all *other* outcome tokens for the seller.
     */
    function _mintToken(
        IController.Order calldata _buyOrder,
        IController.Order calldata _sellOrder,
        uint256 _tokenId,
        uint256 _fillAmount
    ) internal {
        // 1. Mint for buyer token
        uint256[] memory buyerIds = new uint256[](1);
        uint256[] memory buyerAmounts = new uint256[](1);
        buyerIds[0] = _tokenId;
        buyerAmounts[0] = _fillAmount;
        position.mintBatch(_buyOrder.user, buyerIds, buyerAmounts);

        // 2. Mint for seller (all *other* outcomes)
        uint256 numberOfOutcome = market.getOutcomeCount(_sellOrder.marketId);

        uint256[] memory sellerTokenIds = new uint256[](numberOfOutcome - 1);
        uint256[] memory sellerAmounts = new uint256[](numberOfOutcome - 1);
        uint256 index;

        for (uint256 i = 0; i < numberOfOutcome; ++i) {
            if (i == _buyOrder.outcome) continue; // Skip the buyer's outcome

            sellerTokenIds[index] = position.getTokenId(_sellOrder.marketId, i);
            sellerAmounts[index] = _fillAmount;
            index++;
        }

        position.mintBatch(_sellOrder.user, sellerTokenIds, sellerAmounts);
    }
}