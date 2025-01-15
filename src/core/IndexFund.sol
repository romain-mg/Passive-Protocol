// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;
pragma abicoder v2;

import "@uniswap-v3-periphery-1.4.4/libraries/TransferHelper.sol";
import "@uniswap-v3-periphery-1.4.4/interfaces/ISwapRouter.sol";
import "@openzeppelin-contracts-5.2.0-rc.1//utils/ReentrancyGuard.sol";
import "../interfaces/IIndexFund.sol";
import "@chainlink-contracts-1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPSVToken.sol";
import {console} from "forge-std-1.9.5/src/console.sol";

contract IndexFund is IIndexFund, ReentrancyGuard {
    ISwapRouter public immutable swapRouter;

    struct UserData {
        uint256 mintedShares;
        uint256 tokenAAmount;
        uint256 tokenBAmount;
    }

    struct TokenData {
        IERC20 token;
        AggregatorV3Interface priceDataFetcher;
    }

    mapping(bytes32 => TokenData) public tokenTickerToTokenData;
    mapping(address => UserData) public userToUserData;

    uint256 public mintPrice = 1;
    uint256 public rebalancingFee = 1;
    uint256 public mintFeeDivisor = 1000;
    uint24 public uniswapPoolFee = 3000;

    IPSVToken public psvToken;

    bytes32 tokenATicker;
    bytes32 tokenBTicker;
    bytes32 stablecoinTicker;

    event FeeCollected(address indexed user, uint256 indexed feeAmount);

    event SharesMinted(
        address indexed user,
        uint256 indexed amount,
        uint256 indexed stablecoinIn
    );

    event SharesBurned(
        address indexed user,
        uint256 indexed amount,
        uint256 indexed stablecoinReturned
    );

    event Rebalanced(address indexed rebalancer, bool feeSent);

    modifier allowanceChecker(
        address token,
        address allower,
        address allowed,
        uint256 amount
    ) {
        if (IERC20(token).allowance(allower, allowed) < amount) {
            revert("Allowance too small");
        }
        _;
    }

    constructor(
        ISwapRouter _swapRouter,
        address _tokenA,
        address _tokenB,
        address _stablecoin,
        bytes32 _tokenATicker,
        bytes32 _tokenBTicker,
        bytes32 _stablecoinTicker,
        address _psv,
        address _tokenADataFeed,
        address _tokenBDataFeed,
        address _stablecoinDataFeed
    ) {
        swapRouter = _swapRouter;

        tokenATicker = _tokenATicker;
        tokenBTicker = _tokenBTicker;
        stablecoinTicker = _stablecoinTicker;

        tokenTickerToTokenData[tokenATicker].token = IERC20(_tokenA);
        tokenTickerToTokenData[tokenATicker]
            .priceDataFetcher = AggregatorV3Interface(_tokenADataFeed);
        tokenTickerToTokenData[tokenBTicker].token = IERC20(_tokenB);
        tokenTickerToTokenData[tokenBTicker]
            .priceDataFetcher = AggregatorV3Interface(_tokenBDataFeed);
        tokenTickerToTokenData[stablecoinTicker].token = IERC20(_stablecoin);
        tokenTickerToTokenData[stablecoinTicker]
            .priceDataFetcher = AggregatorV3Interface(_stablecoinDataFeed);

        psvToken = IPSVToken(_psv);
    }

    function mintShare(
        uint256 stablecoinAmount
    )
        public
        allowanceChecker(
            address(tokenTickerToTokenData[stablecoinTicker].token),
            msg.sender,
            address(this),
            stablecoinAmount
        )
        nonReentrant
    {
        require(stablecoinAmount > 0, "You need to provide some stablecoin");

        TokenData memory stablecoinData = tokenTickerToTokenData[
            stablecoinTicker
        ];
        IERC20 stablecoin = stablecoinData.token;
        require(
            stablecoin.balanceOf(msg.sender) >= stablecoinAmount,
            "Not enough stablecoin in user wallet"
        );
        bool transferSuccess = stablecoin.transferFrom(
            msg.sender,
            address(this),
            stablecoinAmount
        );
        require(
            transferSuccess,
            "Failed to transfer stablecoin from user wallet"
        );

        (
            uint256 stablecoinToInvest,
            uint256 tokenASwapped,
            uint256 tokenBSwapped
        ) = _investUserStablecoin(stablecoin, stablecoinAmount);

        uint256 sharesToMint = stablecoinToInvest / mintPrice;
        userToUserData[msg.sender].mintedShares += sharesToMint;
        userToUserData[msg.sender].tokenAAmount += tokenASwapped;
        userToUserData[msg.sender].tokenBAmount += tokenBSwapped;

        psvToken.mint(msg.sender, sharesToMint);
        emit SharesMinted(msg.sender, sharesToMint, stablecoinAmount);
    }

    function burnShare(
        uint256 sharesToBurn
    )
        public
        allowanceChecker(
            address(psvToken),
            msg.sender,
            address(this),
            sharesToBurn
        )
    {
        UserData memory userData = userToUserData[msg.sender];
        uint256 userMintedShares = userData.mintedShares;
        require(sharesToBurn <= userMintedShares, "Amount too big");

        TokenData memory stablecoinData = tokenTickerToTokenData[
            stablecoinTicker
        ];
        IERC20 stablecoin = stablecoinData.token;

        (
            uint256 stablecoinToSend,
            uint256 tokenASwapped,
            uint256 tokenBSwapped
        ) = _redeemUserStablecoin(
                stablecoin,
                userMintedShares,
                sharesToBurn,
                userData
            );

        userToUserData[msg.sender].mintedShares -= sharesToBurn;
        userToUserData[msg.sender].tokenAAmount -= tokenASwapped;
        userToUserData[msg.sender].tokenBAmount -= tokenBSwapped;

        psvToken.burn(msg.sender, sharesToBurn);
        bool transferSuccess = stablecoin.transfer(
            msg.sender,
            stablecoinToSend
        );
        require(
            transferSuccess,
            "Failed to transfer stablecoin to user wallet"
        );
        emit SharesBurned(msg.sender, sharesToBurn, stablecoinToSend);
    }

    function rebalance() public nonReentrant {
        uint256 tokenABought = getTokenBought(tokenATicker);
        uint256 tokenBBought = getTokenBought(tokenBTicker);

        uint256 tokenAMarketCap = _getTokenMarketCap(
            tokenTickerToTokenData[tokenATicker],
            tokenATicker
        );
        uint256 tokenBMarketCap = _getTokenMarketCap(
            tokenTickerToTokenData[tokenBTicker],
            tokenBTicker
        );

        uint256 tokenATokenBCorrectRatio = (tokenAMarketCap * 1e18) /
            tokenBMarketCap;

        uint256 tokenAPrice = _getTokenPrice(tokenATicker);
        uint256 tokenBPrice = _getTokenPrice(tokenBTicker);

        uint256 tokenATokenBActualRatio = (tokenAPrice * tokenABought * 1e18) /
            (tokenBPrice * tokenBBought);

        if (
            tokenATokenBActualRatio >= (tokenATokenBCorrectRatio * 98) / 100 &&
            tokenATokenBActualRatio <= (tokenATokenBCorrectRatio * 102) / 100
        ) {
            revert("No need to rebalance");
        }

        if (tokenATokenBActualRatio < (tokenATokenBCorrectRatio * 98) / 100) {
            // Need to sell tokenB to buy tokenA
            uint256 targetTokenABalance = (tokenBPrice *
                tokenBBought *
                tokenAMarketCap) / (tokenBMarketCap * tokenAPrice);

            uint256 tokenBToSell = ((targetTokenABalance - tokenABought) *
                tokenAPrice) / tokenBPrice;

            // Cap swap amount to avoid overselling
            tokenBToSell = tokenBToSell > tokenBBought
                ? tokenBBought
                : tokenBToSell;

            _swap(
                address(tokenTickerToTokenData[tokenBTicker].token),
                address(tokenTickerToTokenData[tokenATicker].token),
                tokenBToSell,
                0, // Minimum output ignored here; adapt in production
                uniswapPoolFee
            );
        } else {
            // Need to sell tokenA to buy tokenB
            uint256 targetTokenBBalance = (tokenAPrice *
                tokenABought *
                tokenBMarketCap) / (tokenAMarketCap * tokenBPrice);

            uint256 tokenAToSell = ((targetTokenBBalance - tokenBBought) *
                tokenBPrice) / tokenAPrice;

            // Cap swap amount to avoid overselling
            tokenAToSell = tokenAToSell > tokenABought
                ? tokenABought
                : tokenAToSell;

            _swap(
                address(tokenTickerToTokenData[tokenATicker].token),
                address(tokenTickerToTokenData[tokenBTicker].token),
                tokenAToSell,
                0, // Minimum output ignored here; adapt in production
                uniswapPoolFee
            );
        }

        IERC20 stablecoin = tokenTickerToTokenData[stablecoinTicker].token;
        if (stablecoin.balanceOf(address(this)) > 0) {
            bool transferSuccess = stablecoin.transfer(
                msg.sender,
                rebalancingFee
            );
            require(
                transferSuccess,
                "Failed to transfer stablecoin to user wallet"
            );
            emit Rebalanced(msg.sender, true);
        } else {
            emit Rebalanced(msg.sender, false);
        }
    }

    function _investUserStablecoin(
        IERC20 stablecoin,
        uint256 stablecoinAmount
    )
        internal
        returns (
            uint256 stablecoinInvested,
            uint256 tokenAAmount,
            uint256 tokenBAmount
        )
    {
        uint256 mintFee = stablecoinAmount / mintFeeDivisor;
        emit FeeCollected(msg.sender, mintFee);

        stablecoinInvested = stablecoinAmount - mintFee;

        TokenData memory tokenAData = tokenTickerToTokenData[tokenATicker];
        TokenData memory tokenBData = tokenTickerToTokenData[tokenBTicker];

        (
            uint256 tokenAPrice,
            uint256 tokenBPrice,
            uint256 amountToInvestInTokenA,
            uint256 amountToInvestInTokenB
        ) = _computeTokenSwapInfoWhenMint(
                tokenAData,
                tokenBData,
                stablecoinInvested
            );

        // To fix: assumes the stablecoin is worth 1 dollar and not the real stablecoin price
        uint256 minimumTokenAOutput = amountToInvestInTokenA / tokenAPrice / 2;
        uint256 minimumTokenBOutput = amountToInvestInTokenB / tokenBPrice / 2;

        tokenAAmount = _swap(
            address(stablecoin),
            address(tokenAData.token),
            amountToInvestInTokenA,
            minimumTokenAOutput,
            uniswapPoolFee
        );
        tokenBAmount = _swap(
            address(stablecoin),
            address(tokenBData.token),
            amountToInvestInTokenB,
            minimumTokenBOutput,
            uniswapPoolFee
        );
    }

    function _redeemUserStablecoin(
        IERC20 stablecoin,
        uint256 userMintedShares,
        uint256 sharesToBurn,
        UserData memory userData
    )
        internal
        returns (
            uint256 stablecoinRedeemed,
            uint256 tokenASold,
            uint256 tokenBSold
        )
    {
        (
            uint256 tokenAPrice,
            uint256 tokenBPrice,
            uint256 tokenAToSell,
            uint256 tokenBToSell
        ) = _computeTokenSwapInfoWhenBurn(
                sharesToBurn,
                userMintedShares,
                userData
            );

        // To fix: assumes the stablecoin is worth 1 dollar and not the real stablecoin price
        uint256 minimumStablecoinOutputA = (tokenAToSell * tokenAPrice) / 2;
        uint256 minimumStablecoinOutputB = (tokenBToSell * tokenBPrice) / 2;

        TokenData memory tokenAData = tokenTickerToTokenData[tokenATicker];
        TokenData memory tokenBData = tokenTickerToTokenData[tokenBTicker];

        uint256 redemmedStablecoin = _swap(
            address(tokenAData.token),
            address(stablecoin),
            tokenAToSell,
            minimumStablecoinOutputA,
            uniswapPoolFee
        ) +
            _swap(
                address(tokenBData.token),
                address(stablecoin),
                tokenBToSell,
                minimumStablecoinOutputB,
                uniswapPoolFee
            );

        return (redemmedStablecoin, tokenAToSell, tokenBToSell);
    }

    function _computeTokenSwapInfoWhenMint(
        TokenData memory tokenAData,
        TokenData memory tokenBData,
        uint256 stablecoinToInvest
    )
        internal
        view
        returns (
            uint256 tokenAPrice,
            uint256 tokenBPrice,
            uint256 amountToInvestInTokenA,
            uint256 amountToInvestInTokenB
        )
    {
        tokenAPrice = _getTokenPrice(tokenATicker);
        tokenBPrice = _getTokenPrice(tokenBTicker);

        uint256 tokenAMarketCap = _getTokenMarketCap(tokenAData, tokenATicker);
        uint256 tokenBMarketCap = _getTokenMarketCap(tokenBData, tokenBTicker);

        amountToInvestInTokenA =
            (stablecoinToInvest * tokenAMarketCap) /
            (tokenAMarketCap + tokenBMarketCap);
        amountToInvestInTokenB = stablecoinToInvest - amountToInvestInTokenA;
    }

    function _computeTokenSwapInfoWhenBurn(
        uint256 sharesToBurn,
        uint256 userMintedShares,
        UserData memory userData
    )
        internal
        view
        returns (
            uint256 tokenAPrice,
            uint256 tokenBPrice,
            uint256 tokenAToSell,
            uint256 tokenBToSell
        )
    {
        tokenAToSell =
            (userData.tokenAAmount * sharesToBurn) /
            userMintedShares;
        tokenBToSell =
            (userData.tokenBAmount * sharesToBurn) /
            userMintedShares;

        tokenAPrice = _getTokenPrice(tokenATicker);
        tokenBPrice = _getTokenPrice(tokenBTicker);
    }

    function _swap(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint24 poolFee
    ) private returns (uint256 amountOut) {
        TransferHelper.safeApprove(tokenA, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenA,
                tokenOut: tokenB,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function _getTokenMarketCap(
        TokenData memory tokenData,
        bytes32 tokenTicker
    ) private view returns (uint256) {
        return
            _getTokenPrice(tokenTicker) *
            _getTokenTotalSupply(tokenData, tokenTicker);
    }

    function _getTokenTotalSupply(
        TokenData memory tokenData,
        bytes32 tokenTicker
    ) private view returns (uint256) {
        require(
            tokenTicker == tokenATicker ||
                tokenTicker == tokenBTicker ||
                tokenTicker == stablecoinTicker,
            "Wrong ticker!"
        );
        if (tokenTicker == bytes32(abi.encodePacked("WBTC"))) {
            return 21_000_000;
        } else if (tokenTicker == bytes32(abi.encodePacked("WETH"))) {
            return 120_450_000;
        }
        return tokenData.token.totalSupply();
    }

    function _getTokenPrice(
        bytes32 tokenTicker
    ) internal view returns (uint256) {
        require(
            tokenTicker == tokenATicker ||
                tokenTicker == tokenBTicker ||
                tokenTicker == stablecoinTicker,
            "Wrong ticker!"
        );
        AggregatorV3Interface tokenDataFeed = tokenTickerToTokenData[
            tokenTicker
        ].priceDataFetcher;
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = tokenDataFeed.latestRoundData();
        require(answer > 0, "Invalid price from oracle");
        return uint256(answer);
    }

    function getUserData(
        address userAddress
    )
        public
        view
        returns (
            uint256 userMintedShares,
            uint256 userTokenAAmount,
            uint256 userTokenBAmount
        )
    {
        UserData memory userData = userToUserData[userAddress];
        return (
            userData.mintedShares,
            userData.tokenAAmount,
            userData.tokenBAmount
        );
    }

    function getSharesMintedNumber() public view returns (uint256) {
        return psvToken.totalSupply();
    }

    function getMintFeeBalance() public view returns (uint256) {
        return
            tokenTickerToTokenData[stablecoinTicker].token.balanceOf(
                address(this)
            );
    }

    function getTokenBought(bytes32 ticker) public view returns (uint256) {
        return tokenTickerToTokenData[ticker].token.balanceOf(address(this));
    }
}
