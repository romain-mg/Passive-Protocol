// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockToken.sol";

contract MockUSDC is MockToken {
    constructor() MockToken("Mock USDC", "MUSDC") {}
}
