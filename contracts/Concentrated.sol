// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

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
        address user,
        address token,
        uint256 amount
    ) public {
        balanceOf[user][token] = amount;
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
            uint256 amountOut
        )
    {
        // --- Compute the Swap --- //

        // Get the current price.
        uint256 currentSqrtPrice = getCurrentSqrtPrice();

        // Get the liquidity at the current price.
        uint256 liquidity = getLiquidityAtSqrtPrice(currentSqrtPrice);

        // Get the next price.
        uint256 nextPrice = getNextSqrtPrice(currentIndex);

        console.log("Calling getSwapAmounts with: ");
        console.log(currentSqrtPrice);
        console.log(liquidity);
        console.log(nextPrice);

        // Get the actual swap amounts.
        (price, amountIn, amountOut) = getSwapAmounts(amount, currentSqrtPrice, nextPrice, liquidity);

        // --- Do the swap --- //

        // Set the current price to the actual price.
        _setSqrtPrice(price);

        // Update the balances.
        balanceOf[msg.sender][token0] -= amountIn;
        balanceOf[msg.sender][token1] += amountOut;
    }

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
    function getNextSqrtPrice(uint256 index) public view returns (uint256 nextPrice) {
        nextPrice = sqrtGrid[index + 1];
    }

    /// @dev Uses the change in the price and the liquidity to derive amounts to swap.
    /// @notice (amountIn, amountOut) = f(nextPrice - currentSqrtPrice, liquidity)
    /// Swapping X in will change the price. Then the change in price will change the Y.
    function getSwapAmounts(
        uint256 swapAmount,
        uint256 currentSqrtPrice,
        uint256 nextPrice,
        uint256 liquidity
    )
        public
        view
        returns (
            uint256 price,
            uint256 amountIn,
            uint256 amountOut
        )
    {
        amountIn = swapAmount;

        uint256 deltaSqrtPrice = getChangeInPriceGivenX(amountIn, liquidity);

        amountOut = getChangeInYGivenChangeInPrice(deltaSqrtPrice, liquidity);

        if (deltaSqrtPrice > (nextPrice - currentSqrtPrice)) price = nextPrice;
        else price = currentSqrtPrice;
    }

    /// @dev Δx= Δ(1/sqrt(Price)) * L
    ///      Δx = (1/(sqrt(PriceNext) - sqrt(priceCurrent)) * L
    ///      Δx / L = 1 / (√P_1 - √P_0)
    ///      (√P_1 - √P_0) = L / Δx
    ///      ΔP = L / Δx
    function getChangeInPriceGivenX(uint256 deltaX, uint256 liquidity) public view returns (uint256 deltaSqrtPrice) {
        deltaSqrtPrice = (liquidity * 1e18) / deltaX; // Unit Math: 1e18 = 1e18 * 1e18 / 1e18
    }

    /// @dev Δy = Δ(sqrt(Price)) * L
    function getChangeInYGivenChangeInPrice(uint256 deltaSqrtPrice, uint256 liquidity)
        public
        view
        returns (uint256 deltaY)
    {
        deltaY = (deltaSqrtPrice * liquidity) / 1e18; // Unit Math: 1e18 = 1e18 * 1e18 / 1e18
    }

    // --- To Do --- //

    /// @dev L = sqrt(xy) = sqrt(k)
    /// Price = y / x
    /// y = Price * x
    /// x = y / Price
    /// L = sqrt(y / Price * y)
    /// L = sqrt(y^2 / Price) = y / sqrt(Price)
    /// y = L * sqrt(Price)
    /// L = sqrt(x * P * x)
    /// L = sqrt(x^2 * P)
    /// L = sqrt(x^2) * sqrt(P)
    /// L = x * sqrt(Price)
    /// liquidity = x * sqrtPrice
    /// x = liquidity / sqrtPrice
    /// x = sqrt(xy) / sqrt(y/x)
    /// x = sqrt(xy / y /x) = sqrt(xxy/y) = sqrt(x^2) = x
    /// xy = k
    /// L = sqrt(xy)
    /// L^2 = xy
    /// x = L^2 / y
    /// y = x / L^2
    /// y = x / sqrt(xy)^2 = x / xy = 1 / y
    /// y = L / sqrt(Price) / L^2
    /// y = L / sqrt(y / x) / L^2
    /// y = L^3 / sqrt(y / x)
    /// sqrt(y / x) = L^3 / y
    /// y / x =
    /// liquidity = L = liquidity we want to mint
    function allocate(
        address to,
        uint256 liquidity,
        uint256 sqrtPrice
    ) public returns (uint256 amount0, uint256 amount1) {
        // Compute token amounts required to mint liquidity at price.
        amount0 = (liquidity * 1e18) / sqrtPrice; // sqrtPrice = 1e18 units
        amount1 = (liquidity * sqrtPrice) / 1e18; // 1e18 * 1e18 / 1e18 = 1e18
        // Set Liquidity at SqrtPrice.
        uint256 normalizedSqrtPrice = sqrtPrice / SCALAR;
        ticks[normalizedSqrtPrice] = liquidity;
        // Handle tokens and minting liquidity.
        balanceOf[to][token0] -= amount0;
        balanceOf[to][token1] -= amount1;
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
