// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IController {
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

    error UnauthorizedCaller();

    error MarketPaused();

    error AmountOrderReached();

    error NonZeroAddress();

    error FeeTooHigh();

    error MarketNotResolvedYet();

    error MismatchAnswer();

    error SenderHasNotBalance();

}
