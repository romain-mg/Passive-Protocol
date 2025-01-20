// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma abicoder v2;

import "@chainlink-contracts-1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin-contracts-5.2.0-rc.1/access/Ownable.sol";
import "@openzeppelin-contracts-5.2.0-rc.1/interfaces/IERC20.sol";
import "../lib/PassiveLibrary.sol";
import "./IndexFund.sol";

contract MarketDataFetcher is Ownable {
    uint256 public immutable wbtcTotalSupply = 21_000_000;
    uint256 public immutable wethTotalSupply = 120_450_000;

    IndexFund indexFund;

    modifier checkTicker(bytes32 tokenTicker) {
        bytes32 tokenATicker = indexFund.tokenATicker();
        bytes32 tokenBTicker = indexFund.tokenBTicker();
        bytes32 stablecoinTicker = indexFund.stablecoinTicker();

        require(
            tokenTicker == tokenATicker ||
                tokenTicker == tokenBTicker ||
                tokenTicker == stablecoinTicker,
            "Wrong ticker!"
        );
        _;
    }

    constructor() Ownable(msg.sender) {
        indexFund = IndexFund(msg.sender);
    }

    function _getTokenMarketCap(
        PassiveLibrary.TokenData memory tokenData,
        bytes32 tokenTicker
    ) public view returns (uint256) {
        return
            _getTokenPrice(tokenTicker) *
            _getTokenTotalSupply(tokenData, tokenTicker);
    }

    function _getTokenTotalSupply(
        PassiveLibrary.TokenData memory tokenData,
        bytes32 tokenTicker
    ) public view checkTicker(tokenTicker) returns (uint256) {
        if (tokenTicker == bytes32(abi.encodePacked("WBTC"))) {
            return 21_000_000;
        } else if (tokenTicker == bytes32(abi.encodePacked("WETH"))) {
            return 120_450_000;
        }
        return tokenData.token.totalSupply();
    }

    function _getTokenPrice(
        bytes32 tokenTicker
    ) public view checkTicker(tokenTicker) returns (uint256) {
        (, AggregatorV3Interface tokenDataFeed) = indexFund
            .tokenTickerToTokenData(tokenTicker);
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = tokenDataFeed.latestRoundData();
        require(answer > 0, "Invalid price from oracle");
        return uint256(answer);
    }
}
