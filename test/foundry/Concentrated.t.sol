// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "../../contracts/Concentrated.sol";

contract TestConcentrated is Test {
    Concentrated public concentrate;

    address public user;
    address public token0;
    address public token1;

    struct UserState {
        uint256 initialBalance0;
        uint256 initialBalance1;
    }

    UserState public userState;

    function setUp() public payable {
        concentrate = new Concentrated();
        vm.prank(address(0));
        vm.deal(address(0), 100 ether);

        user = address(0x01);
        token0 = address(0x04);
        token1 = address(0x05);

        userState.initialBalance0 = 100 ether;
        userState.initialBalance1 = 100 ether;

        concentrate.setTokens(token0, token1);
        concentrate.setBalance(user, token0, userState.initialBalance0);
        concentrate.setBalance(user, token1, userState.initialBalance1);
    }

    uint256 public constant SCALAR = 1e18;

    function allocate(uint256 sqrtPriceIndex) public returns (uint256 amount0, uint256 amount1) {
        // Get balances before allocate.
        uint256 balance0 = concentrate.balanceOf(user, token0);
        uint256 balance1 = concentrate.balanceOf(user, token1);
        uint256 liquidity0 = concentrate.balanceOf(user, address(concentrate));
        uint256 sqrtPrice = concentrate.sqrtGrid(sqrtPriceIndex); // indexed at 0, so 1 = second element.

        vm.prank(user);
        uint256 liquidity = 10; // 10 = sqrt(xy), 100 = xy, x = 10 / sqrtPrice, x = 5, 100 = 5y, y = 20, y = x / 10^2, y = x / 100
        (amount0, amount1) = concentrate.allocate(user, liquidity, sqrtPrice);

        assertEq(concentrate.balanceOf(user, address(concentrate)), liquidity0 + liquidity);
        assertEq(concentrate.balanceOf(user, token0), balance0 - amount0);
        assertEq(concentrate.balanceOf(user, token1), balance1 - amount1);
        assertEq(concentrate.ticks(sqrtPrice), liquidity);
        assertEq(amount0 * amount1, liquidity * liquidity);
    }

    function testAllocate() public {
        (uint256 amount0, uint256 amount1) = allocate(1);
        console.log("Allocated!");
        console.log(amount0);
        console.log(amount1);
    }

    function getReserves(uint256 priceIndex) public view returns (uint256 reserve0, uint256 reserve1) {
        (reserve0, reserve1) = concentrate.getReserves(priceIndex);
        console.log("Getting Reserves for price index", priceIndex);
        console.log("reserve0", reserve0);
        console.log("reserve1", reserve1);
        console.log("Price:", reserve1 / reserve0);
    }

    function testSwap() public {
        // Add liquidity to tick index 1.
        uint256 currentIndex = concentrate.currentIndex();
        allocate(currentIndex); // Index0
        allocate(currentIndex + 1); // Index1

        (uint256 reserve0Index0, uint256 reserve1Index0) = getReserves(currentIndex);
        (uint256 reserve0Index1, uint256 reserve1Index1) = getReserves(currentIndex + 1);

        uint256 priceBefore = concentrate.getCurrentSqrtPrice();

        // Do the swap
        vm.prank(user);
        uint256 amount = 9;
        uint256 limitPrice = 0;
        (uint256 price, uint256 amountIn, uint256 amountOut, uint256 remainder) = concentrate.swap(amount, limitPrice);
        console.log("Swapped!");
        console.log("price", price);
        console.log("amountIn", amountIn);
        console.log("amountOut", amountOut);
        console.log("remainder", remainder);

        uint256 expectedRemainder = reserve0Index0 > amount ? 0 : amount - reserve0Index0;

        bool expectedPriceChange = expectedRemainder > 0;
        bool actualPriceChange = priceBefore != price;

        assertGt(concentrate.balanceOf(user, token1), 0);
        assertEq(remainder, expectedRemainder);
        assertEq(actualPriceChange, expectedPriceChange);
    }
}
