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
    uint256 mockWBTCPricePerUnit;
    uint256 mockWETHPricePerUnit;

    constructor(
        address _mockWBTCAddress,
        address _mockWETHAddress,
        address _mockUSDCAddress,
        uint256 _mockWBTCPricePerUnit,
        uint256 _mockWETHPricePerUnit
    ) {
        mockWBTCAddress = _mockWBTCAddress;
        mockWETHAddress = _mockWETHAddress;
        mockUSDCAddress = _mockUSDCAddress;
        mockWBTCPricePerUnit = _mockWBTCPricePerUnit;
        mockWETHPricePerUnit = _mockWETHPricePerUnit;
    }

    function exactInputSingle(
        ExactInputSingleParams memory params
    ) external payable returns (uint256 amountOut) {
        MockToken mockTokenIn = MockToken(params.tokenIn);
        mockTokenIn.transferFrom(msg.sender, address(this), params.amountIn);
        MockToken(params.tokenIn).burn(params.amountIn);
        if (params.tokenOut == mockWBTCAddress) {
            amountOut = params.amountIn / mockWBTCPricePerUnit;
        } else if (params.tokenOut == mockWETHAddress) {
            if (params.tokenIn == mockWBTCAddress) {
                amountOut =
                    (params.amountIn * mockWBTCPricePerUnit) /
                    mockWETHPricePerUnit;
            } else {
                amountOut = params.amountIn / mockWETHPricePerUnit;
            }
        } else if (params.tokenOut == mockUSDCAddress) {
            if (params.tokenIn == mockWBTCAddress) {
                amountOut = params.amountIn * mockWBTCPricePerUnit;
            } else if (params.tokenIn == mockWETHAddress) {
                amountOut = params.amountIn * mockWETHPricePerUnit;
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
