// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import "../src/IDOFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**decimals());
    }
}

contract IDOFactoryTest is Test {
    IDOFactory public factory;
    MockERC20 public token;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        
        factory = new IDOFactory(owner);
        token = new MockERC20("Test Token", "TEST");
        
        vm.label(address(factory), "IDOFactory");
        vm.label(address(token), "TestToken");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
    }

    function testCreateLBPool() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 startPrice = 100 * 10**18;
        uint256 endPrice = 50 * 10**18;
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        token.approve(address(factory), tokenAmount);

        factory.createLBPool(
            address(token),
            tokenAmount,
            startPrice,
            endPrice,
            startTime,
            endTime
        );

        assertEq(factory.poolCount(), 1);
        
        (
            address poolToken,
            uint256 poolTokenAmount,
            uint256 poolStartPrice,
            uint256 poolEndPrice,
            uint256 poolStartTime,
            uint256 poolEndTime,
            IDOFactory.PoolType poolType,
            bool isActive
        ) = factory.pools(0);

        assertEq(poolToken, address(token));
        assertEq(poolTokenAmount, tokenAmount);
        assertEq(poolStartPrice, startPrice);
        assertEq(poolEndPrice, endPrice);
        assertEq(poolStartTime, startTime);
        assertEq(poolEndTime, endTime);
        assertEq(uint(poolType), uint(IDOFactory.PoolType.LBP));
        assertTrue(isActive);
    }

    function testCreateFixedPricePool() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 price = 75 * 10**18;
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

        token.approve(address(factory), tokenAmount);

        factory.createFixedPricePool(
            address(token),
            tokenAmount,
            price,
            startTime,
            endTime
        );

        assertEq(factory.poolCount(), 1);
        
        (
            address poolToken,
            uint256 poolTokenAmount,
            uint256 poolStartPrice,
            uint256 poolEndPrice,
            uint256 poolStartTime,
            uint256 poolEndTime,
            IDOFactory.PoolType poolType,
            bool isActive
        ) = factory.pools(0);

        assertEq(poolToken, address(token));
        assertEq(poolTokenAmount, tokenAmount);
        assertEq(poolStartPrice, price);
        assertEq(poolEndPrice, price);
        assertEq(poolStartTime, startTime);
        assertEq(poolEndTime, endTime);
        assertEq(uint(poolType), uint(IDOFactory.PoolType.FixedPrice));
        assertTrue(isActive);
    }

    function testBuyTokensLBP() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 startPrice = 1 ether;
        uint256 endPrice = 1000 wei;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 10 days;

        token.approve(address(factory), tokenAmount);

        factory.createLBPool(
            address(token),
            tokenAmount,
            startPrice,
            endPrice,
            startTime,
            endTime
        );

        vm.warp(startTime + 1 seconds);
        vm.deal(user1, 100 ether);

        vm.prank(user1);
        uint256 currentPrice = factory.getCurrentPrice(0);
        console.log("current price: ", currentPrice);
        factory.buyTokens{value: 100 * currentPrice}(0);

        (, uint256 remainingTokens, , , , , , ) = factory.pools(0);
        assertLt(remainingTokens, tokenAmount);
    }

    function testBuyTokensFixedPrice() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 price = 0.1 ether;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 10 days;

        token.approve(address(factory), tokenAmount);

        factory.createFixedPricePool(
            address(token),
            tokenAmount,
            price,
            startTime,
            endTime
        );
        vm.warp(startTime + 1 seconds);

        vm.deal(user2, 10 ether);

        vm.prank(user2);
        
        factory.buyTokens{value: 1 ether}(0);

        (, uint256 remainingTokens, , , , , , ) = factory.pools(0);
        assertEq(remainingTokens, tokenAmount - (1 ether / price));
    }

    function testClosePool() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 price = 0.1 ether;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 10 days;

        token.approve(address(factory), tokenAmount);

        factory.createFixedPricePool(
            address(token),
            tokenAmount,
            price,
            startTime,
            endTime
        );
         vm.warp(endTime+ 1 seconds);

        factory.closePool(0);
       

        (, , , , , , , bool isActive) = factory.pools(0);
        assertFalse(isActive);
    }

    function testFailCreatePoolNonOwner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.createLBPool(
            address(token),
            1000 * 10**18,
            100 * 10**18,
            50 * 10**18,
            block.timestamp + 1 hours,
            block.timestamp + 1 days
        );
    }

    function testFailBuyTokensPoolNotActive() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 price = 0.1 ether;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 10 days;

        token.approve(address(factory), tokenAmount);

        factory.createFixedPricePool(
            address(token),
            tokenAmount,
            price,
            startTime,
            endTime
        );
        vm.warp(endTime + 1 seconds);

        factory.closePool(0);

        vm.deal(user2, 1 ether);
        vm.prank(user2);
        factory.buyTokens{value: 1 ether}(0);

        vm.expectRevert("Pool is not active");
       
    }

    function testGetCurrentPrice() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 startPrice = 100 * 10**18;
        uint256 endPrice = 50 * 10**18;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 10 days;

        token.approve(address(factory), tokenAmount);

        factory.createLBPool(
            address(token),
            tokenAmount,
            startPrice,
            endPrice,
            startTime,
            endTime
        );

        vm.warp(startTime + 12 hours);
        uint256 currentPrice = factory.getCurrentPrice(0);
        console.log("current price:",currentPrice);
        assertEq(currentPrice, 975 * 10**17);
    }
}