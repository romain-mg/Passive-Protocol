// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Test} from "forge-std-1.9.5/src/Test.sol";
import {stdError} from "forge-std-1.9.5/src/StdError.sol";
import "../src/mock/MockWBTC.sol";
import "../src/mock/MockETH.sol";
import "../src/mock/MockUSDC.sol";
import "../src/mock/MockAggregator.sol";

contract IndexFundTest is Test {
    uint256 testNumber;

    function setUp() public {
        mockWBTC = new MockWBTC;
        mockETH = new MockETH;
        mockUSDC = new MockUSDC;
        mockAggregator = new MockAggregator;
    }

    function test_MintShare() public {}

    function test_BurnShare() public {}

    function test_CannotSubtract43() public {
        vm.expectRevert(stdError.arithmeticError);
        testNumber -= 43;
    }
}
