// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockToken.sol";

contract MockWBTC is MockToken {
    uint256 public mockTotalSupply = 21000000;

    constructor() MockToken("Mock WBTC", "MWBTC") {}
}
