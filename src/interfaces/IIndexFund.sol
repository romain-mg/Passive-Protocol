// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIndexFund {
    function mintShare(
        uint256 stablecoinAmount,
        uint256 tokenAPrice,
        uint256 tokenBPrice
    ) external;

    function burnShare(
        uint256 amount,
        bool getBackIndexFundTokens,
        uint256 tokenAPrice,
        uint256 tokenBPrice
    ) external;
}
