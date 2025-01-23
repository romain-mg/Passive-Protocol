// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma abicoder v2;

import "@uniswap-v3-periphery-1.4.4/libraries/TransferHelper.sol";
import "@uniswap-v3-periphery-1.4.4/interfaces/ISwapRouter.sol";
import "@openzeppelin-contracts-5.2.0-rc.1/utils/ReentrancyGuard.sol";
import "@openzeppelin-contracts-5.2.0-rc.1/access/Ownable.sol";
import "@chainlink-contracts-1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPSVToken.sol";
import "../interfaces/IIndexFund.sol";
import "./MarketDataFetcher.sol";
import "../lib/PassiveLibrary.sol";

contract IndexFund is IIndexFund, ReentrancyGuard, Ownable {
    ISwapRouter public immutable swapRouter;

    struct UserData {
        uint256 mintedShares;
        uint256 tokenAAmount;
        uint256 tokenBAmount;
    }

    mapping(bytes32 => PassiveLibrary.TokenData) public tokenTickerToTokenData;
    mapping(address => UserData) public userToUserData;

    uint256 public mintPrice = 1;
    uint256 public mintFeeDivisor = 1000;
    uint24 public uniswapPoolFee = 3000;

    IPSVToken public psvToken;

    MarketDataFetcher marketDataFetcher;

    bytes32 public tokenATicker;
    bytes32 public tokenBTicker;
    bytes32 public stablecoinTicker;

    event FeeCollected(address indexed user, uint256 indexed feeAmount);

    event SharesMinted(
        address indexed user,
        uint256 indexed amount,
        uint256 indexed stablecoinIn
    );

    event SharesBurned(address indexed user, uint256 indexed amount);

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
        address _swapRouter,
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
    ) Ownable(msg.sender) {
        swapRouter = ISwapRouter(_swapRouter);

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

        marketDataFetcher = new MarketDataFetcher();
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

        PassiveLibrary.TokenData memory stablecoinData = tokenTickerToTokenData[
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
        uint256 sharesToBurn,
        bool getBackIndexFundTokens
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

        if (getBackIndexFundTokens) {
            bool tokenATransferSuccess = tokenTickerToTokenData[tokenATicker]
                .token
                .transfer(
                    msg.sender,
                    (userData.tokenAAmount * sharesToBurn) / userMintedShares
                );
            require(
                tokenATransferSuccess,
                "Failed to transfer token A to user wallet"
            );

            bool tokenBTransferSuccess = tokenTickerToTokenData[tokenBTicker]
                .token
                .transfer(
                    msg.sender,
                    (userData.tokenBAmount * sharesToBurn) / userMintedShares
                );
            require(
                tokenBTransferSuccess,
                "Failed to transfer token B to user wallet"
            );
        } else {
            PassiveLibrary.TokenData
                memory stablecoinData = tokenTickerToTokenData[
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

            userToUserData[msg.sender].tokenAAmount -= tokenASwapped;
            userToUserData[msg.sender].tokenBAmount -= tokenBSwapped;

            bool transferSuccess = stablecoin.transfer(
                msg.sender,
                stablecoinToSend
            );
            require(
                transferSuccess,
                "Failed to transfer stablecoin to user wallet"
            );
        }

        userToUserData[msg.sender].mintedShares -= sharesToBurn;
        psvToken.burn(msg.sender, sharesToBurn);

        emit SharesBurned(msg.sender, sharesToBurn);
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

        PassiveLibrary.TokenData memory tokenAData = tokenTickerToTokenData[
            tokenATicker
        ];
        PassiveLibrary.TokenData memory tokenBData = tokenTickerToTokenData[
            tokenBTicker
        ];

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

        uint256 stablecoinPrice = marketDataFetcher._getTokenPrice(
            stablecoinTicker
        );
        tokenAAmount = _swap(
            address(stablecoin),
            address(tokenAData.token),
            amountToInvestInTokenA,
            (amountToInvestInTokenA * stablecoinPrice) / tokenAPrice / 2,
            uniswapPoolFee
        );
        tokenBAmount = _swap(
            address(stablecoin),
            address(tokenBData.token),
            amountToInvestInTokenB,
            (amountToInvestInTokenB * stablecoinPrice) / tokenBPrice / 2,
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

        uint256 minimumStablecoinOutputA = (tokenAToSell * tokenAPrice) / 2;
        uint256 minimumStablecoinOutputB = (tokenBToSell * tokenBPrice) / 2;

        PassiveLibrary.TokenData memory tokenAData = tokenTickerToTokenData[
            tokenATicker
        ];
        PassiveLibrary.TokenData memory tokenBData = tokenTickerToTokenData[
            tokenBTicker
        ];

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
        PassiveLibrary.TokenData memory tokenAData,
        PassiveLibrary.TokenData memory tokenBData,
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
        tokenAPrice = marketDataFetcher._getTokenPrice(tokenATicker);
        tokenBPrice = marketDataFetcher._getTokenPrice(tokenBTicker);

        uint256 tokenAMarketCap = marketDataFetcher._getTokenMarketCap(
            tokenAData,
            tokenATicker
        );
        uint256 tokenBMarketCap = marketDataFetcher._getTokenMarketCap(
            tokenBData,
            tokenBTicker
        );

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

        tokenAPrice = marketDataFetcher._getTokenPrice(tokenATicker);
        tokenBPrice = marketDataFetcher._getTokenPrice(tokenBTicker);
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

    function withdrawFees() public onlyOwner {
        PassiveLibrary.TokenData memory stablecoinData = tokenTickerToTokenData[
            stablecoinTicker
        ];
        IERC20 stablecoin = stablecoinData.token;
        bool transferSuccess = stablecoin.transfer(
            msg.sender,
            stablecoin.balanceOf(address(this))
        );
        require(transferSuccess, "Failed to transfer mint fees to owner");
    }
}
