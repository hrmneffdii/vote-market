// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {Market} from "../src/Market.sol";
import {Resolver} from "../src/Resolver.sol";
import {Position} from "../src/Position.sol";
import {Controller} from "../src/Controller.sol";
import {IController} from "../src/interfaces/IController.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract ControllerTest is Test {
    uint256 constant INITIAL_OUTCOME = 10;
    uint256 constant INITIAL_BALANCE = 1_000_000e6;
    ERC20Mock usdc;

    address owner = makeAddr("owner");
    address oracle = makeAddr("oracle");
    address treasury = makeAddr("treasury");

    address bob;
    address admin;
    address alice;

    uint256 bobPrivateKey = 0xb0b;
    uint256 adminPrivateKey = 0xa1d11;
    uint256 alicePrivateKey = 0xa11ce;

    Vault vault;
    Market market;
    Position position;
    Resolver resolver;
    Controller controller;

    function setUp() external {
        usdc = new ERC20Mock();
        controller = new Controller(owner, treasury);
        market = new Market(owner, address(controller), INITIAL_OUTCOME);
        position = new Position(owner, address(controller));
        vault = new Vault(owner, address(controller));
        resolver = new Resolver(
            owner,
            address(market),
            address(oracle),
            address(controller)
        );

        bob = vm.addr(bobPrivateKey);
        admin = vm.addr(adminPrivateKey);
        alice = vm.addr(alicePrivateKey);

        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(admin, INITIAL_BALANCE);

        vm.startPrank(owner);
        controller.setConfig(market, vault, resolver, position);
        controller.setAdmin(admin, true);
        controller.setFee(1000, 1000);

        vault.setToken(usdc);
        vm.stopPrank();
    }

    function test_initialize() external view {
        assertEq(controller.owner(), owner);
        assertEq(controller.treasury(), treasury);
        assertEq(address(controller.market()), address(market));
        assertEq(address(controller.vault()), address(vault));
        assertEq(address(controller.position()), address(position));
        assertEq(address(controller.resolver()), address(resolver));
        assertEq(controller.paused(), false);
    }

    function test_constructorFails() external {
        vm.expectRevert();
        new Controller(address(0), treasury);

        vm.expectRevert();
        new Controller(owner, address(0));
    }

    function test_setConfigRevert() external {
        vm.expectRevert(); // not owner call
        controller.setConfig(market, vault, resolver, position);

        vm.startPrank(owner);
        vm.expectRevert(); // not owner call
        controller.setConfig(Market(address(0)), vault, resolver, position);

        vm.expectRevert(); // not owner call
        controller.setConfig(
            Market(address(0)),
            Vault(address(0)),
            resolver,
            position
        );

        vm.expectRevert(); // not owner call
        controller.setConfig(
            Market(address(0)),
            vault,
            Resolver(address(0)),
            position
        );

        vm.expectRevert(); // not owner call
        controller.setConfig(
            Market(address(0)),
            vault,
            resolver,
            Position(address(0))
        );

        vm.stopPrank();
    }

    function test_createMarketSuccess() external {
        bytes32 marketId = keccak256("1. is ETH will jump into 10K?");
        uint256 numberOfOutcome = 2;
        uint256 deadline = 30 days;

        vm.expectRevert(); // unauthorized caller
        controller.createMarket(marketId, numberOfOutcome, deadline);

        vm.prank(admin);
        controller.createMarket(marketId, 2, deadline);
    }

    function test_updateDeadlne() external {
        bytes32 marketId = _createMarket(2, 3 days);

        vm.prank(admin);
        controller.updateDeadline(marketId, 5 days);
    }

    function test_resolveMarket() external {
        bytes32 marketId = _createMarket(2, 0);

        vm.prank(admin);
        controller.resolveManually(marketId, 0);
    }

    function test_fillOrderRevertsMarketIsntSame() external {
        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobBuyOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        Controller.Order memory aliceSellOrder = IController.Order({
            user: alice,
            marketId: keccak256("asdas"),
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSignature = _signOrder(bobPrivateKey, bobBuyOrder);
        bytes memory aliceSignature = _signOrder(
            alicePrivateKey,
            aliceSellOrder
        );

        vm.prank(admin);
        vm.expectRevert(); // marketId isn't same
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            aliceSellOrder,
            aliceSignature,
            100e6
        );
    }

    function test_fillOrderRevertsOutcomeIsntSame() external {
        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobBuyOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        Controller.Order memory aliceSellOrder = IController.Order({
            user: alice,
            marketId: marketId,
            outcome: 0,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSignature = _signOrder(bobPrivateKey, bobBuyOrder);
        bytes memory aliceSignature = _signOrder(
            alicePrivateKey,
            aliceSellOrder
        );

        vm.prank(admin);
        vm.expectRevert(); // outcome isn't same
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            aliceSellOrder,
            aliceSignature,
            100e6
        );
    }

    function test_fillOrderRevertsSameBuyOrder() external {
        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobBuyOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        Controller.Order memory aliceSellOrder = IController.Order({
            user: alice,
            marketId: keccak256("asdas"),
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSignature = _signOrder(bobPrivateKey, bobBuyOrder);
        bytes memory aliceSignature = _signOrder(
            alicePrivateKey,
            aliceSellOrder
        );

        vm.prank(admin);
        vm.expectRevert(); // marketId isn't same
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            aliceSellOrder,
            aliceSignature,
            100e6
        );
    }

    function test_fillOrderRevertsIncorrectPrice() external {
        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobBuyOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        Controller.Order memory aliceSellOrder = IController.Order({
            user: alice,
            marketId: keccak256("asdas"),
            outcome: 1,
            amount: 100e6,
            price: 8000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSignature = _signOrder(bobPrivateKey, bobBuyOrder);
        bytes memory aliceSignature = _signOrder(
            alicePrivateKey,
            aliceSellOrder
        );

        vm.prank(admin);
        vm.expectRevert(); // incorrect price
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            aliceSellOrder,
            aliceSignature,
            100e6
        );
    }

    function test_fillOrderRevertsFillAmountZero() external {
        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobBuyOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        Controller.Order memory aliceSellOrder = IController.Order({
            user: alice,
            marketId: keccak256("asdas"),
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSignature = _signOrder(bobPrivateKey, bobBuyOrder);
        bytes memory aliceSignature = _signOrder(
            alicePrivateKey,
            aliceSellOrder
        );

        vm.prank(admin);
        vm.expectRevert(); // fill amount zero isn't same
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            aliceSellOrder,
            aliceSignature,
            0
        );
    }

    function test_fillOrderMintSuccess() external {
        _depositToVault(bob, 100e6);
        _depositToVault(alice, 100e6);

        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobBuyOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        Controller.Order memory aliceSellOrder = IController.Order({
            user: alice,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSignature = _signOrder(bobPrivateKey, bobBuyOrder);
        bytes memory aliceSignature = _signOrder(
            alicePrivateKey,
            aliceSellOrder
        );

        vm.prank(admin);
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            aliceSellOrder,
            aliceSignature,
            100e6
        );

        // balance of token id
        uint256 tokenIdBob = position.getTokenId(marketId, 1); // buy 1
        uint256 tokenIdAlice = position.getTokenId(marketId, 0); // buy complement 1

        assertEq(position.balanceOf(bob, tokenIdBob), 100e6);
        assertEq(position.balanceOf(alice, tokenIdAlice), 100e6);

        // total amount locked
        assertEq(vault.getTotalLocked(marketId), 100e6);

        // balances user in vault
        assertEq(vault.getBalance(bob), 100e6 - 60e6 - 6e6);
        assertEq(vault.getBalance(alice), 100e6 - 40e6 - 4e6);
        assertEq(vault.getBalance(treasury), 10e6);
    }

    function test_fillOrderMintSuccessWithoutTreasury() external {
        vm.prank(owner);
        controller.setTreasury(address(0));

        _depositToVault(bob, 100e6);
        _depositToVault(alice, 100e6);

        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobBuyOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        Controller.Order memory aliceSellOrder = IController.Order({
            user: alice,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSignature = _signOrder(bobPrivateKey, bobBuyOrder);
        bytes memory aliceSignature = _signOrder(
            alicePrivateKey,
            aliceSellOrder
        );

        vm.prank(admin);
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            aliceSellOrder,
            aliceSignature,
            100e6
        );

        // balance of token id
        uint256 tokenIdBob = position.getTokenId(marketId, 1); // buy 1
        uint256 tokenIdAlice = position.getTokenId(marketId, 0); // buy complement 1

        assertEq(position.balanceOf(bob, tokenIdBob), 100e6);
        assertEq(position.balanceOf(alice, tokenIdAlice), 100e6);

        // total amount locked
        assertEq(vault.getTotalLocked(marketId), 100e6);

        // balances user in vault
        assertEq(vault.getBalance(bob), 100e6 - 60e6);
        assertEq(vault.getBalance(alice), 100e6 - 40e6);
        assertEq(vault.getBalance(treasury), 0);
    }

    function test_fillOrderRevertsOrderAmountReached() external {
        (
            bytes32 marketId,
            Controller.Order memory bobBuyOrder,
            ,
            bytes memory bobSignature,
            ,

        ) = _fillOrder();

        Controller.Order memory adminSellOrder = IController.Order({
            user: admin,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory adminSignature = _signOrder(
            adminPrivateKey,
            adminSellOrder
        );

        vm.prank(admin);
        vm.expectRevert();
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            adminSellOrder,
            adminSignature,
            100e6
        );
    }

    function test_fillOrderRevertsOrderAmountReached2() external {
        (
            bytes32 marketId,
            ,
            Controller.Order memory aliceSellOrder,
            ,
            bytes memory aliceSignature,

        ) = _fillOrder();

        Controller.Order memory adminBuyOrder = IController.Order({
            user: admin,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        bytes memory adminSignature = _signOrder(
            adminPrivateKey,
            adminBuyOrder
        );

        vm.prank(admin);
        vm.expectRevert();
        controller.fillOrder(
            adminBuyOrder,
            adminSignature,
            aliceSellOrder,
            aliceSignature,
            100e6
        );
    }

    function test_fillOrderSwapSuccess() external {
        // 1. bob buys outcome 1
        _depositToVault(bob, 100e6);
        _depositToVault(alice, 100e6);
        _depositToVault(admin, 100e6);

        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobBuyOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        Controller.Order memory aliceSellOrder = IController.Order({
            user: alice,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSignature = _signOrder(bobPrivateKey, bobBuyOrder);
        bytes memory aliceSignature = _signOrder(
            alicePrivateKey,
            aliceSellOrder
        );

        vm.prank(admin);
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            aliceSellOrder,
            aliceSignature,
            100e6
        );

        // 2. bob sell outcome 1
        Controller.Order memory bobsellOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSellSignature = _signOrder(bobPrivateKey, bobsellOrder);

        Controller.Order memory adminBuyOrder = IController.Order({
            user: admin,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        bytes memory adminSignature = _signOrder(
            adminPrivateKey,
            adminBuyOrder
        );

        vm.prank(admin);
        controller.fillOrder(
            adminBuyOrder,
            adminSignature,
            bobsellOrder,
            bobSellSignature,
            100e6
        );

        // balance of token id
        uint256 tokenIdAdmin = position.getTokenId(marketId, 1); // buy 1
        uint256 tokenIdAlice = position.getTokenId(marketId, 0); // buy complement 1

        assertEq(position.balanceOf(admin, tokenIdAdmin), 100e6);
        assertEq(position.balanceOf(alice, tokenIdAlice), 100e6);

        // total amount locked
        assertEq(vault.getTotalLocked(marketId), 100e6);
    }

    function test_verifyOrderReverts() external {
        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobsellOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSellSignature = _signOrder(bobPrivateKey, bobsellOrder);

        vm.prank(alice);
        vm.expectRevert(); // unauthorized signer
        controller.verifyOrder(bobsellOrder, bytes("fake signature"));

        skip(7 days);

        vm.expectRevert(); // order expired
        controller.verifyOrder(bobsellOrder, bobSellSignature);
    }

    function test_claimReverts() external {
        (bytes32 marketId, , , , , ) = _fillOrder();

        vm.prank(bob);
        vm.expectRevert(); // market is not resolved yet
        controller.claim(marketId, 1);

        vm.prank(oracle);
        resolver.resolve(marketId, 1); // answer = 1

        vm.prank(alice);
        vm.expectRevert(); // outcome != answer
        controller.claim(marketId, 0);

        vm.prank(alice);
        vm.expectRevert(); // balance == 0
        controller.claim(marketId, 1);
    }

    function test_claimWithoutFee() external {
        (bytes32 marketId, , , , , ) = _fillOrder();

        vm.prank(oracle);
        resolver.resolve(marketId, 1); // answer = 1

        vm.prank(owner);
        controller.setFee(0, 0);

        vm.prank(bob);
        controller.claim(marketId, 1);

        assertEq(vault.getBalance(bob), 134e6); // 100 rewards + 34 remaining
    }

    function test_claimWithFee() external {
        (bytes32 marketId, , , , , ) = _fillOrder();

        vm.prank(oracle);
        resolver.resolve(marketId, 1); // answer = 1

        vm.prank(bob);
        controller.claim(marketId, 1);

        assertGt(vault.getBalance(bob), 0); // 100 rewards + remaining
    }

    function test_cancelOrder() external {
        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobsellOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSellSignature = _signOrder(bobPrivateKey, bobsellOrder);

        vm.expectRevert(); // sender isn't order.user
        controller.cancelOrder(bobsellOrder, bobSellSignature);

        vm.prank(bob);
        controller.cancelOrder(bobsellOrder, bobSellSignature);

        bytes32 hash = controller.verifyOrder(bobsellOrder, bobSellSignature);

        assertEq(controller.filledAmounts(hash), bobsellOrder.amount);
    }

    function _fillOrder()
        internal
        returns (
            bytes32,
            Controller.Order memory,
            Controller.Order memory,
            bytes memory,
            bytes memory,
            uint256
        )
    {
        _depositToVault(bob, 100e6);
        _depositToVault(alice, 100e6);

        bytes32 marketId = _createMarket(2, 0);

        Controller.Order memory bobBuyOrder = IController.Order({
            user: bob,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: true
        });

        Controller.Order memory aliceSellOrder = IController.Order({
            user: alice,
            marketId: marketId,
            outcome: 1,
            amount: 100e6,
            price: 6000,
            nonce: 1,
            expiration: block.timestamp + 1 days,
            isBuy: false
        });

        bytes memory bobSignature = _signOrder(bobPrivateKey, bobBuyOrder);
        bytes memory aliceSignature = _signOrder(
            alicePrivateKey,
            aliceSellOrder
        );

        vm.prank(admin);
        controller.fillOrder(
            bobBuyOrder,
            bobSignature,
            aliceSellOrder,
            aliceSignature,
            100e6
        );

        return (
            marketId,
            bobBuyOrder,
            aliceSellOrder,
            bobSignature,
            aliceSignature,
            100e6
        );
    }

    function _depositToVault(address user, uint256 amount) internal {
        vm.startPrank(user);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    function _createMarket(
        uint256 _numberOfOutcome,
        uint256 _deadlineTime
    ) internal returns (bytes32) {
        bytes32 marketId = keccak256("1. is ETH will jump into 10K?");
        uint256 numberOfOutcome = _numberOfOutcome;
        uint256 deadline = _deadlineTime;

        vm.prank(admin);
        controller.createMarket(marketId, numberOfOutcome, deadline);

        return marketId;
    }

    function _getOrderHash(
        IController.Order memory order
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Order(address user,bytes32 marketId,uint256 outcome,uint256 amount,uint256 price,uint256 nonce,uint256 expiration,bool isBuy)"
                ),
                order.user,
                order.marketId,
                order.outcome,
                order.amount,
                order.price,
                order.nonce,
                order.expiration,
                order.isBuy
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("Controller"),
                keccak256("1"),
                block.chainid,
                address(controller)
            )
        );

        return
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, structHash)
            );
    }

    function _signOrder(
        uint256 _privateKey,
        IController.Order memory _order
    ) internal view returns (bytes memory) {
        bytes32 hash = _getOrderHash(_order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, hash);
        return abi.encodePacked(r, s, v);
    }
}
