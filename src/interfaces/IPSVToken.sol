// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-5.2.0-rc.1/interfaces/IERC20.sol";

interface IPSVToken is IERC20 {
    function mint(address investor, uint256 amount) external;

    function burn(address investor, uint256 amount) external;

    function setIndexFund(address _index_fund) external;
}
