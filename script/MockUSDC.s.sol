// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std-1.9.5/src/Script.sol";
import {MockUSDC} from "../src/mock/MockUSDC.sol";

contract MockUSDCScript is Script {
    function run() external returns (MockUSDC) {
        vm.startBroadcast();

        MockUSDC mockUSDC = new MockUSDC();

        vm.stopBroadcast();
        return mockUSDC;
    }
}
