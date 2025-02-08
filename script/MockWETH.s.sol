// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std-1.9.5/src/Script.sol";
import {MockWETH} from "../src/mock/MockWETH.sol";

contract MockWETHScript is Script {
    function run() external returns (MockWETH) {
        vm.startBroadcast();

        MockWETH mockweth = new MockWETH();

        vm.stopBroadcast();
        return mockweth;
    }
}
