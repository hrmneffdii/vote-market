// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Market} from "./Market.sol";
import {Vault} from "./Vault.sol";
import {Resolver} from "./Resolver.sol";
import {IController} from "./interfaces/IController.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Controller is IController, EIP712, Ownable {
    using ECDSA for bytes32;

    bytes32 private constant ORDER_TYPEHASH =
        keccak256(
            "Order(address user,bytes32 marketId,uint256 outcome,uint256 amount,uint256 price,uint256 nonce,uint256 expiration, bool isBuy)"
        );

    bool public paused;

    uint128 feeTrade;
    uint128 feeClaim;
    address treasury;

    Market public market;
    Vault public vault;
    Resolver public resolver;

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
        Market _market,
        Vault _vault,
        Resolver _resolver
    ) Ownable(_initialOwner) EIP712("Controller", "1") {
        if (address(_market) == address(0)) revert NonZeroAddress();
        if (address(_vault) == address(0)) revert NonZeroAddress();
        if (address(_resolver) == address(0)) revert NonZeroAddress();

        market = _market;
        vault = _vault;
        resolver = _resolver;
    }

    // admin function

    function createMarket(
        bytes32 _marketId,
        uint256 _numberOfOutcome,
        uint256 _deadlineTime
    ) external onlyAdmin {
        market.createMarket(_marketId, _numberOfOutcome, _deadlineTime);
    }

    function fillOrder(
        IController.Order calldata _buyOrder,
        bytes calldata _buySignature,
        IController.Order calldata _sellOrder,
        bytes calldata _sellSignature,
        uint256 _fillAmounts
    ) external onlyAdmin whenNotPaused {
        // check
        require(_buyOrder.marketId == _sellOrder.marketId);
        require(_buyOrder.outcome == _sellOrder.outcome);
        require(_buyOrder.isBuy && !_sellOrder.isBuy);
        require(_buyOrder.price >= _sellOrder.price);
        require(_fillAmounts > 0);

        bytes32 buyHash = _verifyOrder(_buyOrder, _buySignature);
        bytes32 sellHash = _verifyOrder(_sellOrder, _sellSignature);

        if (filledAmounts[buyHash] + _fillAmounts > _buyOrder.amount)
            revert AmountOrderReached();
        if (filledAmounts[sellHash] + _fillAmounts > _sellOrder.amount)
            revert AmountOrderReached();

        // effect

        // interaction
        _transfer();
    }

    function matchOrder() external onlyAdmin whenNotPaused {}

    function resolveManually(bytes32 _marketId, uint256 _answer) external onlyAdmin whenNotPaused {
        resolver.resolve(_marketId, _answer);
    }

    // user function
    function claim() external whenNotPaused {}

    function cancelOrder() external {}

    // internal function
    function _verifyOrder(
        IController.Order calldata order,
        bytes calldata signature
    ) internal view returns (bytes32) {
        // Check expiration
        // @audit-ok for check expiration
        require(block.timestamp <= order.expiration, "Order expired");

        // Generate order hash
        // @audit-ok the order is good
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

        // Verify signature
        // @audit-ok for checking sender
        address signer = orderHash.recover(signature);
        require(signer == order.user, "Invalid signature");

        // good for returning orderHash
        return orderHash;
    }

    function _executeTrade() internal {}

    function _transfer() internal {}
}
