// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-5.2.0-rc.1/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(
        string memory tokenName,
        string memory tokenTicker
    ) ERC20(tokenName, tokenTicker) {}

    function mint(uint256 amount) public {
        super._mint(msg.sender, amount);
    }
}
