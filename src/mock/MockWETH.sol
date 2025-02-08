// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockToken.sol";

contract MockWETH is MockToken {
    uint256 public mockTotalSupply = 120450000;

    constructor() MockToken("Mock WETH", "MWETH") {}
}
