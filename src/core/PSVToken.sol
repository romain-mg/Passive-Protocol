// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract PSVToken is ERC20, AccessControl {
    bytes32 public constant INDEX_FUND_ROLE = keccak256("INDEX_FUND_ROLE");
    address index_fund;

    constructor() ERC20("PSV Token", "PSV") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(
        address investor,
        uint256 amount
    ) public onlyRole(INDEX_FUND_ROLE) {
        super._mint(investor, amount);
    }

    function burn(
        address investor,
        uint256 amount
    ) public onlyRole(INDEX_FUND_ROLE) {
        _burn(investor, amount);
    }

    function setIndexFund(
        address _index_fund
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_index_fund != address(0)) {
            _revokeRole(INDEX_FUND_ROLE, _index_fund);
        }
        _grantRole(INDEX_FUND_ROLE, _index_fund);
        index_fund = _index_fund;
    }
}
