// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std-1.9.5/src/Script.sol";
import {IndexFund} from "../src/core/IndexFund.sol";

contract IndexFundScript is Script {
    function run() external returns (IndexFund) {
        vm.startBroadcast();

        IndexFund indexFund = new IndexFund(
            address(0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d),
            address(0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d),
            address(0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d),
            address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
            bytes32("WBTC"),
            bytes32("WETH"),
            bytes32("USDC"),
            address(0x14Cb0047D5af2FeD23DffB3FE4Ea63C3bAB2D549)
        );

        vm.stopBroadcast();
        return indexFund;
    }
}
