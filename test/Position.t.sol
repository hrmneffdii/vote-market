// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Position} from "../src/Position.sol";

contract PositionTest is Test {
    address user = makeAddr("user");
    address owner = makeAddr("owner");
    address controller = makeAddr("controller");

    Position position;

    function setUp() external {
        position = new Position(owner, controller);
    }

    function test_initializeFails() external {
        vm.expectRevert();
        new Position(address(0), controller);

        vm.expectRevert();
        new Position(owner, address(0));
    }

    function test_initialize() external view {
        assertEq(position.controller(), controller);
        assertEq(position.owner(), owner);
    }

    function test_setConfig() external {
        address newController = makeAddr("newController");

        vm.expectRevert();
        position.setController(newController);

        vm.prank(owner);
        vm.expectRevert();
        position.setController(address(0));
        
        vm.prank(owner);
        position.setController(newController);

        assertEq(position.controller(), newController);
    }

    function test_mintBatchAndBurn() external {
        bytes32 marketId = keccak256("question");
        uint256 outcome = 2;
        uint256 amount = 100e18;

        uint256 tokenId = position.getTokenId(marketId, outcome);
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.prank(controller);
        position.mintBatch(user, ids, amounts);

        assertEq(position.balanceOf(user, tokenId), amount);

        vm.prank(controller);
        position.burn(user, tokenId, amount);

        assertEq(position.balanceOf(user, tokenId), 0);
    }

    function test_mintBatchAndBurnReverts() external {
        bytes32 marketId = keccak256("question");
        uint256 outcome = 2;
        uint256 amount = 100e18;

        uint256 tokenId = position.getTokenId(marketId, outcome);
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.expectRevert();
        position.mintBatch(user, ids, amounts);

        vm.prank(controller);
        position.mintBatch(user, ids, amounts);

        assertEq(position.balanceOf(user, tokenId), amount);

        vm.expectRevert();
        position.burn(user, tokenId, amount);

        vm.prank(controller);
        position.burn(user, tokenId, amount);

        assertEq(position.balanceOf(user, tokenId), 0);
    }

    function test_mintBatchAndBurnBatch() external {
        bytes32 marketId = keccak256("question");
        uint256 outcome = 2;
        uint256 amount = 100e18;

        uint256 tokenId = position.getTokenId(marketId, outcome);
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.prank(controller);
        position.mintBatch(user, ids, amounts);

        assertEq(position.balanceOf(user, tokenId), amount);

        vm.prank(controller);
        position.burnBatch(user, ids, amounts);

        assertEq(position.balanceOf(user, tokenId), 0);
    }

    function test_mintBatchAndBurnBatchReverts() external {
        bytes32 marketId = keccak256("question");
        uint256 outcome = 2;
        uint256 amount = 100e18;

        uint256 tokenId = position.getTokenId(marketId, outcome);
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.expectRevert();
        position.mintBatch(user, ids, amounts);

        vm.prank(controller);
        position.mintBatch(user, ids, amounts);

        assertEq(position.balanceOf(user, tokenId), amount);


        vm.expectRevert();
        position.burnBatch(user, ids, amounts);

        vm.prank(controller);
        position.burnBatch(user, ids, amounts);

        assertEq(position.balanceOf(user, tokenId), 0);
    }
}
