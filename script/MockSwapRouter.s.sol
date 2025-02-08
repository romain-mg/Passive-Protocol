// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std-1.9.5/src/Script.sol";
import {MockSwapRouter} from "../src/mock/MockSwapRouter.sol";

contract MockSwapRouterScript is Script {
    function run() external returns (MockSwapRouter) {
        vm.startBroadcast();

        address mockWBTC = address(0x80b183bC0c337547e56ab3f882fFCf49774f801f);
        address mockWETH = address(0x64Dd0f86C755954A829be7Ad66d26af21f4171Af);
        address mockUSDC = address(0xB51180D6bF71011B88C51Ab441DE18755Bd5F30F);

        MockSwapRouter mockSwapRouter = new MockSwapRouter(
            mockWBTC,
            mockWETH,
            mockUSDC,
            100,
            35
        );

        address swapRouterAddress = address(
            0xb9b93839B58C49a3157c743E78abaA51CA50549C
        );

        vm.stopBroadcast();
        return mockSwapRouter;
    }
}
