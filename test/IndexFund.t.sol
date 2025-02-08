// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std-1.9.5/src/Test.sol";
import {Vm} from "forge-std-1.9.5/src/Vm.sol";
import {stdError} from "forge-std-1.9.5/src/StdError.sol";
import "../src/mock/MockWBTC.sol";
import "../src/mock/MockWETH.sol";
import "../src/mock/MockUSDC.sol";
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
    MockSwapRouter mockSwapRouter;
    PSVToken psv;
    IndexFund indexFund;

    address defaultSender;

    uint256 usdcMintAmount = 100000;
    uint256 mockWBTCPrice = 100;
    uint256 mockWETHPrice = 3;

    function setUp() public {
        mockWBTC = new MockWBTC();
        mockWETH = new MockWETH();
        mockUSDC = new MockUSDC();
        mockSwapRouter = new MockSwapRouter(
            address(mockWBTC),
            address(mockWETH),
            address(mockUSDC),
            mockWBTCPrice,
            mockWETHPrice
        );
        psv = new PSVToken();
        indexFund = new IndexFund(
            address(mockSwapRouter),
            address(mockWBTC),
            address(mockWETH),
            address(mockUSDC),
            bytes32(abi.encodePacked("WBTC")),
            bytes32(abi.encodePacked("WETH")),
            bytes32(abi.encodePacked("USDC")),
            address(psv),
            1,
            1000,
            3000
        );

        psv.transferOwnership(address(indexFund));
        mockUSDC.mint(address(this), usdcMintAmount);
        defaultSender = address(this);
    }

    function test_MintShareNoAllowance() public {
        vm.expectRevert("Allowance too small");
        indexFund.mintShare(1, mockWBTCPrice, mockWETHPrice);
    }

    function test_MintShareZeroAmount() public {
        vm.expectRevert("You need to provide some stablecoin");
        indexFund.mintShare(0, mockWBTCPrice, mockWETHPrice);
    }

    function test_MintShareNotEnoughStablecoinInWallet() public {
        mockUSDC.approve(address(indexFund), 99999999999);
        uint256 mintPrice = indexFund.mintPrice();
        vm.expectRevert("Not enough stablecoin in user wallet");
        indexFund.mintShare(
            99999999999 / mintPrice,
            mockWBTCPrice,
            mockWETHPrice
        );
    }

    function test_Mint999Shares() public {
        mockUSDC.approve(address(indexFund), 1000);
        indexFund.mintShare(1000, mockWBTCPrice, mockWETHPrice);
        (uint256 mintedShares, , ) = indexFund.getUserData(defaultSender);
        assertEq(indexFund.getMintFeeBalance(), 1);
        assertEq(mintedShares, 999);
        assertEq(mockUSDC.balanceOf(address(indexFund)), 1);
        uint256 mockWBTCMarketCap = mockWBTCPrice * mockWBTC.mockTotalSupply();
        uint256 mockWETHMarketCap = mockWETHPrice * mockWETH.mockTotalSupply();
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
            (mockWBTCUserDataBalance * mockWBTCPrice) /
                (mockWETHUserDataBalance * mockWETHPrice)
        );
    }

    function test_fuzzMintShares(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 1e30);
        mockUSDC.mint(address(this), amount);
        mockUSDC.approve(address(indexFund), amount);
        indexFund.mintShare(amount, mockWBTCPrice, mockWETHPrice);
        (uint256 mintedShares, , ) = indexFund.getUserData(defaultSender);

        uint256 expectedFee = amount / 1000;
        uint256 actualFee = indexFund.getMintFeeBalance();
        assertEq(expectedFee, actualFee);

        assertEq(mintedShares, amount - actualFee);
        assertEq(mockUSDC.balanceOf(address(indexFund)), actualFee);

        uint256 mockWBTCMarketCap = mockWBTCPrice * mockWBTC.mockTotalSupply();
        uint256 mockWETHMarketCap = mockWETHPrice * mockWETH.mockTotalSupply();
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
            (mockWBTCUserDataBalance * mockWBTCPrice) /
                (mockWETHUserDataBalance * mockWETHPrice)
        );
    }

    function test_BurnShareNoAllowance() public {
        vm.expectRevert("Allowance too small");
        indexFund.burnShare(1, false, mockWBTCPrice, mockWETHPrice);
    }

    function test_BurnShareNoSharesMinted() public {
        psv.approve(address(indexFund), 99999);
        vm.expectRevert("Amount too big");
        indexFund.burnShare(1, false, mockWBTCPrice, mockWETHPrice);
    }

    function test_Burn999Shares() public {
        psv.approve(address(indexFund), 99999);
        mockUSDC.approve(address(indexFund), 1000);
        indexFund.mintShare(1000, mockWBTCPrice, mockWETHPrice);
        indexFund.burnShare(999, false, mockWBTCPrice, mockWETHPrice);
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
        uint256 usdcGivenBackAmount = usdcMintAmount - 52;
        // -1 to take into account the minting fee
        assertEq(mockUSDC.balanceOf(address(this)), usdcGivenBackAmount - 1);
    }

    function test_fuzzBurnShares(uint256 amount) public {
        vm.assume(amount > 140 && amount < 1e30);

        mockUSDC.mint(address(this), amount);
        psv.approve(address(indexFund), amount);
        mockUSDC.approve(address(indexFund), amount);
        indexFund.mintShare(amount, mockWBTCPrice, mockWETHPrice);
        // to take into account that the generic setup mints usdc
        assertEq(mockUSDC.balanceOf(address(this)), usdcMintAmount);
        (
            uint256 beforeMintedShares,
            uint256 wbtcBeforeBalance,
            uint256 wethBeforeBalance
        ) = indexFund.getUserData(defaultSender);
        indexFund.burnShare(
            beforeMintedShares,
            false,
            mockWBTCPrice,
            mockWETHPrice
        );
        (
            uint256 afterMintedShares,
            uint256 wbtcAfterBalance,
            uint256 wethAfterBalance
        ) = indexFund.getUserData(defaultSender);

        assertEq(afterMintedShares, 0);
        assertEq(mockWBTC.balanceOf(address(indexFund)), 0);
        assertEq(mockWETH.balanceOf(address(indexFund)), 0);
        assertEq(
            mockUSDC.balanceOf(address(this)),
            mockWBTCPrice *
                wbtcBeforeBalance +
                mockWETHPrice *
                wethBeforeBalance +
                usdcMintAmount
        );
        // assertEq(mockUSDC.balanceOf(address(indexFund)), fee);
        assertEq(wbtcAfterBalance, 0);
        assertEq(wethAfterBalance, 0);
    }

    function test_fuzzBurnSharesRedeemIndexTokens(uint256 amount) public {
        vm.assume(amount > 100 && amount < 1e30);

        mockUSDC.mint(address(this), amount);
        psv.approve(address(indexFund), amount);
        mockUSDC.approve(address(indexFund), amount);
        indexFund.mintShare(amount, mockWBTCPrice, mockWETHPrice);

        (
            uint256 beforeMintedShares,
            uint256 beforeWBTCBalance,
            uint256 beforeWETHBalance
        ) = indexFund.getUserData(defaultSender);

        indexFund.burnShare(
            beforeMintedShares,
            true,
            mockWBTCPrice,
            mockWETHPrice
        );

        (uint256 afterMintedShares, , ) = indexFund.getUserData(defaultSender);
        uint256 wbtcAfterBurnBalance = mockWBTC.balanceOf(address(this));
        uint256 wethAfterBurnBalance = mockWETH.balanceOf(address(this));

        assertEq(afterMintedShares, 0);
        assertTrue(
            wbtcAfterBurnBalance == beforeWBTCBalance &&
                wethAfterBurnBalance == beforeWETHBalance
        );
    }
}
