// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;
import "@uniswap-v3-periphery-1.4.4/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery-1.4.4/libraries/TransferHelper.sol";
import "./MockToken.sol";

contract MockSwapRouter is ISwapRouter {
    function exactInputSingle(
        ExactInputSingleParams memory params
    ) external payable returns (uint256 amountOut) {
        MockToken tokenIn = MockToken(params.tokenIn);
        MockToken tokenOut = MockToken(params.tokenOut);
        tokenIn.transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = params.amountIn;
        tokenOut.mint(amountOut);
        tokenOut.transfer(msg.sender, amountOut);
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
