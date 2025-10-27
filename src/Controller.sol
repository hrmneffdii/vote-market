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

contract Controller is IController, EIP712, Ownable {
    using ECDSA for bytes32;

    bytes32 private constant ORDER_TYPEHASH =
        keccak256(
            "Order(address user,bytes32 marketId,uint256 outcome,uint256 amount,uint256 price,uint256 nonce,uint256 expiration,bool isBuy)"
        );

    bool public paused;

    uint256 constant BPS = 10_000;

    uint128 feeTrade;

    uint128 feeClaim;

    address treasury;

    Vault public vault;

    Market public market;

    Resolver public resolver;

    Position public position;

    mapping(address => bool) whitelistedAdmin;

    mapping(bytes32 => uint256) filledAmounts;

    modifier onlyAdmin() {
        if (!whitelistedAdmin[msg.sender]) revert UnauthorizedCaller();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert MarketPaused();
        _;
    }

    constructor(
        address _initialOwner,
        address _treasury,
        Market _market,
        Vault _vault,
        Resolver _resolver,
        Position _position
    ) Ownable(_initialOwner) EIP712("Controller", "1") {
        if (address(_initialOwner) == address(0)) revert NonZeroAddress();
        if (address(_treasury) == address(0)) revert NonZeroAddress();
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

    // owner function
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function setFee(uint128 _feeTrade, uint128 _feeClaim) external onlyOwner {
        if (_feeTrade > 1000 || _feeClaim > 1000) revert FeeTooHigh();

        feeTrade = _feeTrade;
        feeClaim = _feeClaim;
    }

    function setTreasury(address _treasury) external onlyOwner {
        // allowing treasury is set to address zero
        treasury = _treasury;
    }

    function setMarket(Market _market) external onlyOwner {
        if (address(_market) == address(0)) revert NonZeroAddress();

        market = _market;
    }

    function setVault(Vault _vault) external onlyOwner {
        if (address(_vault) == address(0)) revert NonZeroAddress();

        vault = _vault;
    }

    function setResolver(Resolver _resolver) external onlyOwner {
        if (address(_resolver) == address(0)) revert NonZeroAddress();

        resolver = _resolver;
    }

    function setPosition(Position _position) external onlyOwner {
        if (address(_position) == address(0)) revert NonZeroAddress();

        position = _position;
    }

    function setAdmin(address _admin, bool _whitelisted) external onlyOwner {
        whitelistedAdmin[_admin] = _whitelisted;
    }

    // admin function
    function createMarket(
        bytes32 _marketId,
        uint256 _numberOfOutcome,
        uint256 _deadlineTime
    ) external onlyAdmin {
        market.createMarket(_marketId, _numberOfOutcome, _deadlineTime);
    }

    function updateDeadline(
        bytes32 _marketId,
        uint256 _deadlineTime
    ) external onlyAdmin {
        market.updateDeadlineTime(_marketId, _deadlineTime);
    }

    function fillOrder(
        IController.Order calldata _buyOrder,
        bytes calldata _buySignature,
        IController.Order calldata _sellOrder,
        bytes calldata _sellSignature,
        uint256 _fillAmount
    ) external onlyAdmin whenNotPaused {
        // Check
        require(_buyOrder.marketId == _sellOrder.marketId);
        require(_buyOrder.outcome == _sellOrder.outcome);
        require(_buyOrder.isBuy && !_sellOrder.isBuy);
        require(_buyOrder.price >= _sellOrder.price);
        require(_fillAmount > 0);

        bytes32 buyHash = _verifyOrder(_buyOrder, _buySignature);
        bytes32 sellHash = _verifyOrder(_sellOrder, _sellSignature);

        if (filledAmounts[buyHash] + _fillAmount > _buyOrder.amount)
            revert AmountOrderReached();
        if (filledAmounts[sellHash] + _fillAmount > _sellOrder.amount)
            revert AmountOrderReached();

        // Effect
        filledAmounts[buyHash] += _fillAmount;
        filledAmounts[sellHash] += _fillAmount;

        // Interaction
        uint256 tokenId = position.getTokenId(
            _buyOrder.marketId,
            _buyOrder.outcome
        );
        uint256 balanceOfSeller = position.balanceOf(_sellOrder.user, tokenId);

        if (balanceOfSeller >= _fillAmount) {
            _swapToken(_buyOrder, _sellOrder, tokenId, _fillAmount);
        } else {
            _mintToken(_buyOrder, _sellOrder, tokenId, _fillAmount);
        }

        // 3. interaction
        uint256 priceForBuyer = _fillAmount * _buyOrder.price;
        uint256 priceForSeller = _fillAmount * _sellOrder.price;

        vault.lock(_buyOrder.marketId, _buyOrder.user, priceForBuyer);
        vault.lock(_sellOrder.marketId, _sellOrder.user, priceForSeller);

        if (feeTrade > 0 && treasury != address(0)) {
            _takesFee(_buyOrder, _sellOrder, priceForBuyer, priceForSeller);
        }
    }

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

    function cancelOrder(
        IController.Order calldata _order,
        bytes calldata _signature
    ) external {
        if (_order.user != msg.sender) revert UnauthorizedCaller();

        bytes32 orderHash = _verifyOrder(_order, _signature);

        filledAmounts[orderHash] = _order.amount;
    }

    function resolveManually(
        bytes32 _marketId,
        uint256 _answer
    ) external onlyAdmin whenNotPaused {
        resolver.resolve(_marketId, _answer);
    }

    // user function
    function claim(bytes32 _marketId, uint256 _outcome) external whenNotPaused {
        if (!resolver.isResolved(_marketId)) revert MarketNotResolvedYet();

        uint256 answer = resolver.getAnswer(_marketId);
        if (answer != _outcome) revert MismatchAnswer();

        uint256 tokenId = position.getTokenId(_marketId, _outcome);

        uint256 balance = position.balanceOf(msg.sender, tokenId);

        if (balance == 0) revert SenderHasNotBalance();

        uint256 fee = (balance * feeClaim) / BPS;

        if (fee > 0 && treasury != address(0)) {
            vault.release(_marketId, msg.sender, balance);
            vault.transfer(_marketId, msg.sender, treasury, fee);
        }

        position.burn(msg.sender, tokenId, balance);
    }

    // internal function
    function _verifyOrder(
        IController.Order calldata order,
        bytes calldata signature
    ) internal view returns (bytes32) {
        require(block.timestamp <= order.expiration, "Order expired");

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
        require(signer == order.user, "Invalid signature");

        return orderHash;
    }

    function _swapToken(
        IController.Order calldata _buyOrder,
        IController.Order calldata _sellOrder,
        uint256 _tokenId,
        uint256 _fillAmount
    ) internal {
        // 1, burn seller token
        position.burn(_sellOrder.user, _tokenId, _fillAmount);

        // 2. mint buyer token
        position.mint(_buyOrder.user, _tokenId, _fillAmount);
    }

    function _mintToken(
        IController.Order calldata _buyOrder,
        IController.Order calldata _sellOrder,
        uint256 _tokenId,
        uint256 _fillAmount
    ) internal {
        // 1. mint for buyer token
        position.mint(_buyOrder.user, _tokenId, _fillAmount);

        // 2. mint for seller token
        uint256 numberOfOutcome = market.getOutcomeCount(_sellOrder.marketId);
        uint256[] memory tokenIds = new uint256[](numberOfOutcome - 1);
        uint256[] memory amounts = new uint256[](numberOfOutcome - 1);
        uint256 index;

        for (uint256 i = 0; i < numberOfOutcome; ++i) {
            if (i == _buyOrder.outcome) continue;

            tokenIds[index] = position.getTokenId(_sellOrder.marketId, i);
            amounts[index] = _fillAmount;
            index += 1;
        }

        position.mintBatch(_sellOrder.user, tokenIds, amounts);
    }
}
