// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

library TokenDataFetcher {
    function _getTokenMarketCap(
        uint256 tokenPrice,
        IERC20 token,
        bytes32 tokenTicker
    ) public view returns (uint256) {
        return tokenPrice * _getTokenTotalSupply(token, tokenTicker);
    }

    function _getTokenTotalSupply(
        IERC20 token,
        bytes32 tokenTicker
    ) public view returns (uint256) {
        if (tokenTicker == bytes32(abi.encodePacked("WBTC"))) {
            return 21_000_000;
        } else if (tokenTicker == bytes32(abi.encodePacked("WETH"))) {
            return 120_450_000;
        }
        return token.totalSupply();
    }
}
