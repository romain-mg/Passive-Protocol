// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink-contracts-1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin-contracts-5.2.0-rc.1/interfaces/IERC20.sol";

library PassiveLibrary {
    struct TokenData {
        IERC20 token;
        AggregatorV3Interface priceDataFetcher;
    }
}
