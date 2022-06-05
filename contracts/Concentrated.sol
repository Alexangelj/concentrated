// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

contract Concentrated {
    constructor() payable {}

    /// @notice Account -> Price -> Liquidity.
    /// @dev Maps an account to a mapping of a price with liquidity at it.
    mapping(address => mapping(uint256 => uint256)) public positions;

    /// @dev Maps a price to liquidity.
    mapping(uint256 => uint256) public ticks;

    function allocate(
        address to,
        uint256 amount,
        uint256 price
    ) public {
        positions[to][price] += amount;
        ticks[price] += amount;
    }

    function swap(
        uint8 direction,
        uint256 amount,
        uint256 price
    ) public {}

    function remove(uint256 amount, uint256 price) public {
        positions[msg.sender][price] -= amount; // This reverts if msg.sender does not have liquidity at price.
        ticks[price] -= amount; // This reverts if tick[price] does not have enough liquidity.
    }
}
