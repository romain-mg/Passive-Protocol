// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;
import "@uniswap-v3-periphery-1.4.4/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery-1.4.4/libraries/TransferHelper.sol";
import "./MockToken.sol";
import {console} from "forge-std-1.9.5/src/console.sol";

contract MockSwapRouter is ISwapRouter {
    address mockWBTCAddress;
    address mockWETHAddress;
    address mockUSDCAddress;
    uint256 mockWBTCPrice;
    uint256 mockWETHPrice;

    constructor(
        address _mockWBTCAddress,
        address _mockWETHAddress,
        address _mockUSDCAddress
    ) {
        mockWBTCAddress = _mockWBTCAddress;
        mockWETHAddress = _mockWETHAddress;
        mockUSDCAddress = _mockUSDCAddress;
        mockWBTCPrice = 100;
        mockWETHPrice = 4;
    }

    function exactInputSingle(
        ExactInputSingleParams memory params
    ) external payable returns (uint256 amountOut) {
        MockToken(params.tokenIn).burn(msg.sender, params.amountIn);
        if (params.tokenOut == mockWBTCAddress) {
            amountOut = params.amountIn / mockWBTCPrice;
        } else if (params.tokenOut == mockWETHAddress) {
            if (params.tokenIn == mockWBTCAddress) {
                amountOut = (params.amountIn * mockWBTCPrice) / mockWETHPrice;
            } else {
                amountOut = params.amountIn / mockWETHPrice;
            }
        } else if (params.tokenOut == mockUSDCAddress) {
            if (params.tokenIn == mockWBTCAddress) {
                amountOut = params.amountIn * mockWBTCPrice;
            } else if (params.tokenIn == mockWETHAddress) {
                amountOut = params.amountIn * mockWETHPrice;
            }
        }
        MockToken(params.tokenOut).mint(msg.sender, amountOut);
    }

    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint256 amountOut) {
        amountOut = params.amountIn;
    }

    function exactOutputSingle(
        ExactOutputSingleParams memory params
    ) external payable returns (uint256 amountIn) {
        amountIn = params.amountOut;
    }

    function exactOutput(
        ExactOutputParams calldata params
    ) external payable returns (uint256 amountIn) {
        amountIn = params.amountOut;
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {}
}
