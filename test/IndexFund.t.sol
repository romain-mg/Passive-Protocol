// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std-1.9.5/src/Test.sol";
import {Vm} from "forge-std-1.9.5/src/Vm.sol";
import {stdError} from "forge-std-1.9.5/src/StdError.sol";
import "../src/mock/MockWBTC.sol";
import "../src/mock/MockWETH.sol";
import "../src/mock/MockUSDC.sol";
import "../src/mock/MockWBTCAggregatorV3.sol";
import "../src/mock/MockWETHAggregatorV3.sol";
import "../src/mock/MockUSDCAggregatorV3.sol";
import "../src/mock/MockSwapRouter.sol";
import "@uniswap-v3-periphery-1.4.4/libraries/TransferHelper.sol";
import "../src/core/IndexFund.sol";
import "../src/core/PSVToken.sol";
import "@uniswap-v3-periphery-1.4.4/interfaces/ISwapRouter.sol";
import {console} from "forge-std-1.9.5/src/console.sol";

contract IndexFundTest is Test {
    MockWBTC mockWBTC;
    MockWETH mockWETH;
    MockUSDC mockUSDC;
    MockWBTCAggregatorV3 mockWBTCAggregator;
    MockWETHAggregatorV3 mockWETHAggregator;
    MockUSDCAggregatorV3 mockUSDCAggregator;
    MockSwapRouter mockSwapRouter;
    PSVToken psv;
    IndexFund indexFund;

    address defaultSender;

    uint256 usdcMintAmount = 100000;

    function setUp() public {
        mockWBTC = new MockWBTC();
        mockWETH = new MockWETH();
        mockUSDC = new MockUSDC();
        mockWBTCAggregator = new MockWBTCAggregatorV3();
        mockWETHAggregator = new MockWETHAggregatorV3();
        mockUSDCAggregator = new MockUSDCAggregatorV3();
        mockSwapRouter = new MockSwapRouter(
            address(mockWBTC),
            address(mockWETH),
            address(mockUSDC)
        );
        psv = new PSVToken();
        indexFund = new IndexFund(
            ISwapRouter(mockSwapRouter),
            address(mockWBTC),
            address(mockWETH),
            address(mockUSDC),
            bytes32(abi.encodePacked("WBTC")),
            bytes32(abi.encodePacked("WETH")),
            bytes32(abi.encodePacked("USDC")),
            address(psv),
            address(mockWBTCAggregator),
            address(mockWETHAggregator),
            address(mockUSDCAggregator)
        );

        psv.setIndexFund(address(indexFund));
        mockUSDC.mint(address(this), usdcMintAmount);
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
        (uint256 mintedShares, , ) = indexFund.getUserData(defaultSender);
        assertEq(indexFund.getMintFeeBalance(), 1);
        assertEq(mintedShares, 999);
        assertEq(mockUSDC.balanceOf(address(indexFund)), 1);

        (, int256 mockWBTCPrice, , , ) = mockWBTCAggregator.latestRoundData();
        (, int256 mockWETHPrice, , , ) = mockWETHAggregator.latestRoundData();
        uint256 mockWBTCMarketCap = uint256(mockWBTCPrice) *
            mockWBTC.mockTotalSupply();
        uint256 mockWETHMarketCap = uint256(mockWETHPrice) *
            mockWETH.mockTotalSupply();
        (
            ,
            uint256 mockWBTCUserDataBalance,
            uint256 mockWETHUserDataBalance
        ) = indexFund.userToUserData(address(this));

        // Assert if user data correctly updates balances
        assertEq(
            mockWBTC.balanceOf(address(indexFund)),
            mockWBTCUserDataBalance
        );
        assertEq(
            mockWETH.balanceOf(address(indexFund)),
            mockWETHUserDataBalance
        );

        // Assert if token ratios are correct according to the market cap of the tokens
        assertEq(
            mockWBTCMarketCap / mockWETHMarketCap,
            (mockWBTCUserDataBalance * uint256(mockWBTCPrice)) /
                (mockWETHUserDataBalance * uint256(mockWETHPrice))
        );
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
        // To take into account that in mock swapper, all input token is burnt when you swap so you may not
        // retrieve your full value when swapping back
        uint256 usdcGivenBackAmount = usdcMintAmount - 15;
        // -1 to take into account the minting fee
        assertEq(mockUSDC.balanceOf(address(this)), usdcGivenBackAmount - 1);
    }

    function test_rebalance() public {
        psv.approve(address(indexFund), 99999);
        mockUSDC.approve(address(indexFund), 1000);
        indexFund.mintShare(1000);
        mockWBTC.mint(address(this), 1000);
        // mockWBTC.transfer(address(indexFund), 1000);

        (, int256 mockWBTCPrice, , , ) = mockWBTCAggregator.latestRoundData();
        (, int256 mockWETHPrice, , , ) = mockWETHAggregator.latestRoundData();
        uint256 mockWBTCMarketCap = uint256(mockWBTCPrice) *
            mockWBTC.mockTotalSupply();
        uint256 mockWETHMarketCap = uint256(mockWETHPrice) *
            mockWETH.mockTotalSupply();
        uint256 correctWBTCToWETHRatio = mockWBTCMarketCap / mockWETHMarketCap;

        mockWBTC.mint(address(indexFund), 10);
        console.log(
            "Before wbtc balance",
            mockWBTC.balanceOf(address(indexFund))
        );
        console.log(
            "Before weth balance",
            mockWETH.balanceOf(address(indexFund))
        );
        uint256 beforeRebalancingWBTCToWETHRatio = (uint256(mockWBTCPrice) *
            mockWBTC.balanceOf(address(indexFund))) /
            (uint256(mockWETHPrice) * mockWETH.balanceOf(address(indexFund)));
        assertNotEq(correctWBTCToWETHRatio, beforeRebalancingWBTCToWETHRatio);
        indexFund.rebalance();
        uint256 afterRebalancingWBTCToWETHRatio = (uint256(mockWBTCPrice) *
            mockWBTC.balanceOf(address(indexFund))) /
            (uint256(mockWETHPrice) * mockWETH.balanceOf(address(indexFund)));
        console.log(
            "After wbtc balance",
            mockWBTC.balanceOf(address(indexFund))
        );
        console.log(
            "After weth balance",
            mockWETH.balanceOf(address(indexFund))
        );
        assertEq(correctWBTCToWETHRatio, afterRebalancingWBTCToWETHRatio);
    }
}
