// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std-1.9.5/src/Script.sol";
import {IndexFund} from "../src/core/IndexFund.sol";

contract IndexFundScript is Script {
    function run() external returns (IndexFund) {
        vm.startBroadcast();

        IndexFund indexFund = new IndexFund(
            address(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f),
            address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
            address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
            bytes32("WBTC"),
            bytes32("WETH"),
            bytes32("USDC"),
            address(0xaE5252c9c1534E22385c3F2f8Bd646be11d01b78),
            address(0xd0C7101eACbB49F3deCcCc166d238410D6D46d57),
            address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
            address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3)
        );

        vm.stopBroadcast();
        return indexFund;
    }
}
