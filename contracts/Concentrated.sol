// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "hardhat/console.sol";

/// @dev Used for testing!
contract Context {
    address public token0;
    address public token1;

    address public user;

    /// @dev User => Token => Balance.
    mapping(address => mapping(address => uint256)) public balanceOf;

    function setTokens(address token0_, address token1_) public {
        token0 = token0_;
        token1 = token1_;
    }

    function setBalance(
        address to,
        address token,
        uint256 amount
    ) public {
        balanceOf[to][token] = amount;
    }
}

contract Concentrated is Context {
    constructor() payable {}

    /// @notice Account => Price => Liquidity.
    /// @dev Maps an account to a mapping of a price with liquidity at it.
    mapping(address => mapping(uint256 => uint256)) public positions;

    /// @notice Price => Liquidity.
    /// @dev Maps a price to liquidity.
    mapping(uint256 => uint256) public ticks;

    /// @dev Our prices, where index = where the current price is.
    uint256[5] public grid = [1, 4, 9, 16, 25];

    /// @dev Our sqrt price grid!
    uint256[5] public sqrtGrid = [1, 2, 3, 4, 5];

    /// @dev Starts at 0, so currentSqrtPrice = grid[0] = 1.
    uint256 public currentIndex;

    // --- Stream #2 --- //

    /// @dev Token0 => Token1 Swaps
    function swap(uint256 amount, uint256 limitPrice)
        public
        returns (
            uint256 price,
            uint256 amountIn,
            uint256 amountOut,
            uint256 remainder
        )
    {
        // --- Compute the Swap --- //

        // Get the current price.
        uint256 currentSqrtPrice = getCurrentSqrtPrice();

        // Get the liquidity at the current price.
        uint256 liquidity = getLiquidityAtSqrtPrice(currentSqrtPrice);

        // Get the next price.
        uint256 nextSqrtPrice = getNextSqrtPrice(currentIndex);

        console.log("Calling getSwapAmounts with: ");
        console.log("current sqrtPrice", currentSqrtPrice);
        console.log("liquidity", liquidity);
        console.log("next sqrtPrice", nextSqrtPrice);

        // Get the actual swap amounts.
        (price, amountIn, amountOut, remainder) = getSwapAmounts(amount, currentSqrtPrice, nextSqrtPrice, liquidity);

        // --- Do the swap --- //

        // Set the current price to the actual price.
        _setSqrtPrice(price);

        // Update the balances.
        if (balanceOf[msg.sender][token0] < amountIn) revert BalanceError(balanceOf[msg.sender][token0], amountIn); // for debugging

        // User pays and receives the tokens swapped.
        balanceOf[msg.sender][token0] -= amountIn;
        balanceOf[msg.sender][token1] += amountOut;
        // This contract also pays and receives the tokens swapped.
        balanceOf[address(this)][token0] += amountIn;
        balanceOf[address(this)][token1] -= amountOut;

        // Todo: Use limit price.
        limitPrice;
    }

    error BalanceError(uint256 bal, uint256 less);

    error SetPriceError();

    function _setSqrtPrice(uint256 desiredPrice) public returns (bool success) {
        unchecked {
            uint256 gridLength = sqrtGrid.length;
            // Loop over the sqrtGrid.
            for (uint256 i; i != gridLength; ++i) {
                // Get the price at the index we are at.
                uint256 priceOnGrid = sqrtGrid[i];
                // Compare the price at the index with the desired price.
                if (desiredPrice == priceOnGrid) {
                    // Set the current index if the prices match.
                    currentIndex = i;
                    success = true;
                    break;
                }
            }
        }

        if (!success) revert SetPriceError();
    }

    /// @dev For now, just use a state variable to track this information.
    function getCurrentSqrtPrice() public view returns (uint256) {
        return sqrtGrid[currentIndex];
    }

    /// @dev Lookup some data structure using price as its key and return some liquidity amount.
    function getLiquidityAtSqrtPrice(uint256 sqrtPrice) public view returns (uint256 liquidity) {
        liquidity = ticks[sqrtPrice];
    }

    /// @dev Lookup next higher price given a price.
    function getNextSqrtPrice(uint256 index) public view returns (uint256 nextSqrtPrice) {
        nextSqrtPrice = sqrtGrid[index + 1];
    }

    /// @dev Uses the change in the price and the liquidity to derive amounts to swap.
    /// @notice (amountIn, amountOut) = f(nextSqrtPrice - currentSqrtPrice, liquidity)
    /// Swapping X in will change the price. Then the change in price will change the Y.
    function getSwapAmounts(
        uint256 swapAmount,
        uint256 currentSqrtPrice,
        uint256 nextSqrtPrice,
        uint256 liquidity
    )
        public
        view
        returns (
            uint256 price,
            uint256 amountIn,
            uint256 amountOut,
            uint256 remainder
        )
    {
        // Get full change in the sqrt price by swapping `swapAmount` of x in.
        uint256 fullDeltaSqrtPrice = getChangeInPriceGivenX(swapAmount, liquidity);

        // Get the maximum delta in the sqrt price, which is difference between the neighboring ticks.
        uint256 deltaSqrtPrice = nextSqrtPrice - currentSqrtPrice;

        // If the full price change is more than the tick price change, next price is the next sqrt price.
        uint256 normalizedDeltaSqrtPrice = deltaSqrtPrice * 1e18;
        console.log(fullDeltaSqrtPrice, normalizedDeltaSqrtPrice);
        if (fullDeltaSqrtPrice < normalizedDeltaSqrtPrice) price = nextSqrtPrice;
        // Compute amounts that changed given the change in sqrt price and amount of liquidity.
        (amountIn, amountOut) = getAmountsGivenSqrtPriceAndLiquidity(deltaSqrtPrice, liquidity);

        // If price is equal to next sqrt price, then set the remainder to be less the amountIn
        if (price == nextSqrtPrice) remainder = swapAmount - amountIn;
        else price = currentSqrtPrice; // Else we stay within this price tick, and remainder stays at 0.
    }

    /// @dev Δx= Δ(1/sqrt(Price)) * L
    ///      Δx = (1/(sqrt(PriceNext) - sqrt(priceCurrent)) * L
    ///      Δx / L = 1 / (√P_1 - √P_0)
    ///      (√P_1 - √P_0) = L / Δx
    ///      ΔP = L / Δx
    function getChangeInPriceGivenX(uint256 deltaX, uint256 liquidity) public pure returns (uint256 deltaSqrtPrice) {
        deltaSqrtPrice = (liquidity * 1e18) / deltaX; // Unit Math: 1e18 = 1e18 * 1e18 / 1e18
    }

    /// @dev Computes actual virtual reserves in state.
    function getReserves(uint256 sqrtPriceIndex) public view returns (uint256 reserve0, uint256 reserve1) {
        uint256 sqrtPrice = sqrtGrid[sqrtPriceIndex];
        uint256 liquidity = ticks[sqrtPrice];
        (reserve0, reserve1) = getAmountsGivenSqrtPriceAndLiquidity(sqrtPrice, liquidity);
    }

    /// @dev Computes theoretical virtual reserves given sqrt price and liquidity.
    ///      Handles computing deltas or values! So change in x or x given some change in sqrt price or sqrt price.
    ///      Δx = L * Δ(1/sqrt(Price))
    ///      Δy = L * Δ(sqrt(Price))
    function getAmountsGivenSqrtPriceAndLiquidity(uint256 sqrtPrice, uint256 liquidity)
        public
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 normalizedSqrtPrice = sqrtPrice * SCALAR;
        amount0 = (liquidity * SCALAR) / normalizedSqrtPrice;
        amount1 = (liquidity * normalizedSqrtPrice) / SCALAR;
    }

    // --- To Do --- //

    /// @dev L = sqrt(xy) = sqrt(k)
    /// Price = y / x
    /// L = sqrt(y / Price * y)
    /// L = sqrt(y^2 / Price) = y / sqrt(Price)
    /// L = sqrt(x * P * x)
    /// L = sqrt(x^2 * P)
    /// L = sqrt(x^2) * sqrt(P)
    /// L = x * sqrt(Price)
    /// x = L / sqrt(Price) <------- Use this to compute amount0
    /// y = L * sqrt(Price) <------- Use this to compute amount1
    /// liquidity = L = liquidity we want to mint
    function allocate(
        address to,
        uint256 liquidity,
        uint256 sqrtPrice
    ) public returns (uint256 amount0, uint256 amount1) {
        // Compute token amounts required to mint liquidity at price.
        (amount0, amount1) = getAmountsGivenSqrtPriceAndLiquidity(sqrtPrice, liquidity);
        // Add Liquidity at SqrtPrice.
        ticks[sqrtPrice] += liquidity;
        // Tokens are taken from user
        balanceOf[msg.sender][token0] -= amount0;
        balanceOf[msg.sender][token1] -= amount1;
        // Tokens go in this contract
        balanceOf[address(this)][token0] += amount0;
        balanceOf[address(this)][token1] += amount1;
        // This contract is a liquidity token, give liquidity to `to`.
        balanceOf[to][address(this)] += liquidity;

        emit Allocate(to, sqrtPrice, liquidity);
    }

    uint256 public constant SCALAR = 1e18;

    event Allocate(address indexed to, uint256 sqrtPrice, uint256 liquidity);

    function remove(uint256 amount, uint256 price) public {
        positions[msg.sender][price] -= amount; // This reverts if msg.sender does not have liquidity at price.
        ticks[price] -= amount; // This reverts if tick[price] does not have enough liquidity.
    }
}
