// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-5.2.0-rc.1/token/ERC20/ERC20.sol";

contract MockETH is ERC20 {
    uint256 mockTotalSupply = 120450000;

    constructor() ERC20("Mock ETH", "METH") {}

    function mint(uint256 amount) public {
        super._mint(msg.sender, amount);
    }
}
