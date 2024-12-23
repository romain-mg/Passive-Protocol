// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockETH is ERC20 {
    uint256 totalSupply = 000000 // WHAT IS THE ETH SUPPLY??

    constructor() ERC20("Mock ETH", "METH") {}

    function mint(
        uint256 amount
    ) public {
        super._mint(msg.sender, amount);
    }
}
