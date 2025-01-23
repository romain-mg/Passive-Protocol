// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std-1.9.5/src/Script.sol";
import {PSVToken} from "../src/core/PSVToken.sol";

contract PSVTokenScript is Script {
    function run() external returns (PSVToken) {
        vm.startBroadcast();

        PSVToken pSVToken = new PSVToken();

        vm.stopBroadcast();
        return pSVToken;
    }
}
