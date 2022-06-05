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

        vm.prank(user);
        uint256 liquidity = 10; // 10 = sqrt(xy), 100 = xy, x = 10 / sqrtPrice, x = 5, 100 = 5y, y = 20, y = x / 10^2, y = x / 100
        uint256 sqrtPrice = concentrate.sqrtGrid(sqrtPriceIndex) * SCALAR; // indexed at 0, so 1 = second element.
        (amount0, amount1) = concentrate.allocate(user, liquidity, sqrtPrice);

        uint256 normalizedSqrtPrice = sqrtPrice / SCALAR;

        assertEq(concentrate.balanceOf(user, address(concentrate)), liquidity0 + liquidity);
        assertEq(concentrate.balanceOf(user, token0), balance0 - amount0);
        assertEq(concentrate.balanceOf(user, token1), balance1 - amount1);
        assertEq(concentrate.ticks(normalizedSqrtPrice), liquidity);
        assertEq(amount0 * amount1, liquidity * liquidity);
    }

    function testAllocate() public {
        (uint256 amount0, uint256 amount1) = allocate(1);
        console.log("Allocated!");
        console.log(amount0);
        console.log(amount1);
    }

    function testChangeInPriceGivenX() public {
        uint256 currentIndex = concentrate.currentIndex();
        allocate(currentIndex);

        uint256 deltaX = 10;
        uint256 liquidity = concentrate.ticks(concentrate.sqrtGrid(currentIndex));
        uint256 deltaSqrtPrice = concentrate.getChangeInPriceGivenX(deltaX, liquidity);
        console.log(deltaSqrtPrice);

        assertGt(deltaSqrtPrice, 0);

        uint256 deltaY = concentrate.getChangeInYGivenChangeInPrice(deltaSqrtPrice, liquidity);
        console.log(deltaY);
    }

    function testSwap() public {
        // Add liquidity to tick index 1.
        uint256 currentIndex = concentrate.currentIndex();
        allocate(currentIndex);
        allocate(currentIndex + 1);

        // Do the swap
        vm.prank(user);
        uint256 amount = 10;
        uint256 limitPrice = 0;
        (uint256 price, uint256 amountIn, uint256 amountOut) = concentrate.swap(amount, limitPrice);
        console.log("Swapped!");
        console.log(price);
        console.log(amountIn);
        console.log(amountOut);

        assertGt(concentrate.balanceOf(user, token1), 0);
    }
}
