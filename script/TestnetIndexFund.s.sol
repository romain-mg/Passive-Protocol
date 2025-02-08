// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std-1.9.5/src/Script.sol";
import {IndexFund} from "../src/core/IndexFund.sol";

contract IndexFundScript is Script {
    function run() external returns (IndexFund) {
        vm.startBroadcast();

        address mockWBTC = address(0x80b183bC0c337547e56ab3f882fFCf49774f801f);
        address mockWETH = address(0x64Dd0f86C755954A829be7Ad66d26af21f4171Af);
        address mockUSDC = address(0xB51180D6bF71011B88C51Ab441DE18755Bd5F30F);

        address mockPSV = address(0xb858038541E6dbEC545b64D3a0b682b5b631bEE5);
        address mockSwapRouter = address(
            0xb9b93839B58C49a3157c743E78abaA51CA50549C
        );
        uint256 mintPrice = 1;
        uint256 mintFeeDivisor = 1000;
        uint24 uniswapPoolFee = 3000;

        IndexFund indexFund = new IndexFund(
            mockSwapRouter,
            mockWBTC,
            mockWETH,
            mockUSDC,
            bytes32("WBTC"),
            bytes32("WETH"),
            bytes32("USDC"),
            mockPSV,
            mintPrice,
            mintFeeDivisor,
            uniswapPoolFee
        );

        vm.stopBroadcast();
        return indexFund;
    }
}
