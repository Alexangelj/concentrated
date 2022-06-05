# Concentrated AMM

What's a concentrated AMM? Well, it means liquidity at prices. Those prices are derived from the tokens in the reserves.

## Spec

### Allocate

Add tokens to reserves at some price and give me liquidity tokens.

### Swap

Input some tokens and get some tokens out at a specific price.

### Remove

Remove tokens from the reserves, burn my liquidity at some price.

### Uniswap V3 reference

- Tracks sqrt(Price) instead of reserves.
- Ticks are mapped to prices with the formula 1.0001^i -> 0.01% -> 1 bps difference in prices
- Ticks are ordered by price, which lets us loop through them when we swap.
- Something like Price = Y / X
- L = sqrt(XY) = (L^1)^2 = ( XY^(1/2) )^2 = L^2 = XY
- sqrt(Price) = sqrt(Y/X)
- L^2 = XY
- L^2 = k
- XY=k
- L^2 / Y = X
- L^2 / X = Y
- X = L / sqrt(Price)
- X = L / sqrt(Y / X)
- X^2 = L^2 / (Y / X)
- X^2 = L^2 \* X / Y
- X = L^2 / Y
- (X + deltaX) = L^2 / (Y - deltaY)

- L = sqrt(Y / X) \* X
- Y = L \* sqrt(Price)
- Y = L \* sqrt(XY)
- L = Y / sqrt(XY)

Swap X -> Y

- (X + deltaX) = L / sqrt((Y - deltaY) / X)

```
liquidityToMint = 100
reserve0 = 50
reserve1 = 50
totalLiquidity = L = sqrt(XY) = 50
amount0 = liquidityToMint * reserve0 / totalLiquidity = 100 * 50 / 50 = 100
amount1 = liquidityToMint * reserve1 / totalLiquidity = 100 * 50 / 50 = 100

liquidityToMint = amount0 * totalLiquidity / reserve0 = 100 * 50 / 50 = 100
liquidityToMint = amount1 * totalLiquidity / reserve1 = 100 * 50 / 50 = 100
```

### Price & Reserves

We have reserves X and Y. We have a Price.

`Price = Y / X`

`X = Y / Price`

`Y = X * Price`

Swap

`deltaX + X = (Y - delatY) / Price`
`deltaY + Y = (X - delatX) * Price`

## Problem

- No way to loop over the prices and see how much liquidity there is.
