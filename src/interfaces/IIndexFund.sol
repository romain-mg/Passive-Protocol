pragma solidity ^0.8.7;

interface IIndexFund {
    function mintShare(uint256 stablecoinAmount) external;

    function burnShare(uint256 amount) external;
}
