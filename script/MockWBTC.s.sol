// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std-1.9.5/src/Script.sol";
import {MockWBTC} from "../src/mock/MockWBTC.sol";

contract MockWBTCScript is Script {
    function run() external returns (MockWBTC) {
        vm.startBroadcast();

        MockWBTC mockwbtc = new MockWBTC();

        vm.stopBroadcast();
        return mockwbtc;
    }
}
