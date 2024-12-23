// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// solhint-disable-next-line interface-starts-with-i
contract MockAggregatorV3 {
    function latestRoundData()
        external
        pure
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, 10, 0, 0, 0);
    }
}
