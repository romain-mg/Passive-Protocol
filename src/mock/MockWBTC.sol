// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PSVToken is ERC20 {
    uint256 totalSupply = 21000000 // NEED TO RAISE TO POWER OF 18 OR NOT?

    constructor() ERC20("Mock WBTC", "MWBTC") {}

    function mint(
        uint256 amount
    ) public {
        super._mint(msg.sender, amount);
    }
}
