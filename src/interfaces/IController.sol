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



    // admin function

    function createMarket() external ;
    
    function fillOrder() external ;

    function matchOrder() external ;

    function resolveManually() external ;

    // user function
    function claim() external ;

    function cancelOrder() external ;
}