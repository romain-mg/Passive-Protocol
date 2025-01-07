// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std-1.9.5/src/Test.sol";
import {Vm} from "forge-std-1.9.5/src/Vm.sol";
import {stdError} from "forge-std-1.9.5/src/StdError.sol";
import "../src/mock/MockWBTC.sol";
import "../src/mock/MockWETH.sol";
import "../src/mock/MockUSDC.sol";
import "../src/mock/MockAggregatorV3.sol";
import "../src/mock/MockSwapRouter.sol";
import "@uniswap-v3-periphery-1.4.4/libraries/TransferHelper.sol";
import "../src/core/IndexFund.sol";
import "../src/core/PSVToken.sol";
import "@uniswap-v3-periphery-1.4.4/interfaces/ISwapRouter.sol";

contract IndexFundTest is Test {
    MockWBTC mockWBTC;
    MockWETH mockWETH;
    MockUSDC mockUSDC;
    MockAggregatorV3 mockAggregator;
    MockSwapRouter mockSwapRouter;
    PSVToken psv;
    IndexFund indexFund;

    address defaultSender;

    uint256 usdcMintAmount = 100000;

    function setUp() public {
        mockWBTC = new MockWBTC();
        mockWETH = new MockWETH();
        mockUSDC = new MockUSDC();
        mockAggregator = new MockAggregatorV3();
        mockSwapRouter = new MockSwapRouter();
        psv = new PSVToken();
        indexFund = new IndexFund(
            ISwapRouter(mockSwapRouter),
            address(mockWBTC),
            address(mockWETH),
            address(mockUSDC),
            "WBTC",
            "WETH",
            "USDC",
            address(psv),
            address(mockAggregator),
            address(mockAggregator),
            address(mockAggregator)
        );

        psv.setIndexFund(address(indexFund));
        mockUSDC.mint(usdcMintAmount);
        defaultSender = address(this);
    }

    function test_MintShareNoAllowance() public {
        vm.expectRevert("Allowance too small");
        indexFund.mintShare(1);
    }

    function test_MintShareZeroAmount() public {
        vm.expectRevert("You need to provide some stablecoin");
        indexFund.mintShare(0);
    }

    function test_MintShareNotEnoughStablecoinInWallet() public {
        mockUSDC.approve(address(indexFund), 99999999999);
        uint256 mintPrice = indexFund.mintPrice();
        vm.expectRevert("Not enough stablecoin in user wallet");
        indexFund.mintShare(99999999999 / mintPrice);
    }

    function test_Mint999Shares() public {
        mockUSDC.approve(address(indexFund), 1000);
        indexFund.mintShare(1000);
        (
            uint256 mintedShares,
            uint256 tokenAAmount,
            uint256 tokenBAmount
        ) = indexFund.getUserData(defaultSender);
        assertEq(indexFund.mintFeeBalance(), 1);
        assertEq(mintedShares, 999);
        assertEq(mockUSDC.balanceOf(address(indexFund)), 1);

        (, int256 mockTokenPrice, , , ) = mockAggregator.latestRoundData();
        uint256 mockWBTCMarketCap = uint256(mockTokenPrice) * 21_000_000;
        uint256 mockWETHMarketCap = uint256(mockTokenPrice) * 120_450_000;
        uint256 amountWBTCSwapped = (999 * mockWBTCMarketCap) /
            (mockWBTCMarketCap + mockWETHMarketCap);
        uint256 amountWETHSwapped = 999 - amountWBTCSwapped;

        assertEq(mockWBTC.balanceOf(address(indexFund)), amountWBTCSwapped);
        assertEq(mockWETH.balanceOf(address(indexFund)), amountWETHSwapped);
        assertEq(tokenAAmount, amountWBTCSwapped);
        assertEq(tokenBAmount, amountWETHSwapped);
    }

    function test_BurnShareNoAllowance() public {
        vm.expectRevert("Allowance too small");
        indexFund.burnShare(1);
    }

    function test_BurnShareNoSharesMinted() public {
        psv.approve(address(indexFund), 99999);
        vm.expectRevert("Amount too big");
        indexFund.burnShare(1);
    }

    function test_Burn999Shares() public {
        psv.approve(address(indexFund), 99999);
        mockUSDC.approve(address(indexFund), 1000);
        indexFund.mintShare(1000);
        indexFund.burnShare(999);
        (
            uint256 mintedShares,
            uint256 tokenAAmount,
            uint256 tokenBAmount
        ) = indexFund.getUserData(defaultSender);

        assertEq(mintedShares, 0);
        assertEq(mockWBTC.balanceOf(address(indexFund)), 0);
        assertEq(mockWETH.balanceOf(address(indexFund)), 0);
        assertEq(mockUSDC.balanceOf(address(indexFund)), 1);
        assertEq(tokenAAmount, 0);
        assertEq(tokenBAmount, 0);
        assertEq(mockUSDC.balanceOf(address(this)), usdcMintAmount - 1);
    }
}
