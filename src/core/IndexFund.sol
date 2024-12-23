// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "@uniswap-v3-periphery-1.4.4/libraries/TransferHelper.sol";
import "@uniswap-v3-periphery-1.4.4/interfaces/ISwapRouter.sol";
import "@openzeppelin-contracts-5.2.0-rc.1//utils/ReentrancyGuard.sol";
import "../interfaces/IIndexFund.sol";
import "@chainlink-contracts-1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPSVToken.sol";

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

    mapping(string => TokenData) tokenTickerToTokenData;
    mapping(address => UserData) userToUserData;

    uint256 mintFeeBalance;
    uint256 public immutable mintPrice = 1;

    IPSVToken public psvToken;

    string tokenATicker;
    string tokenBTicker;
    string stablecoinTicker;

    event FeeCollected(address user, uint256 feeAmount);

    event ShareMinted(address user, uint256 amount, uint256 stablecoinIn);

    event SharesBurned(
        address user,
        uint256 amount,
        uint256 stablecoinReturned
    );

    event RebalancedtokenBSold(
        uint256 tokenBSold,
        uint256 tokenABought,
        address caller
    );

    event RebalancedtokenASold(
        uint256 tokenASold,
        uint256 tokenBBought,
        address caller
    );

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
        string memory _tokenATicker,
        string memory _tokenBTicker,
        string memory _stablecoinTicker,
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
        stablecoin.transferFrom(msg.sender, address(this), stablecoinAmount);

        uint256 mintFee = stablecoinAmount / 1000;
        mintFeeBalance += mintFee;

        uint256 tokenAMarketCap = _computeTokenMarketCap(tokenATicker);
        uint256 tokenBMarketCap = _computeTokenMarketCap(tokenBTicker);

        uint256 tokenAIndexShare = (tokenAMarketCap * 100) /
            (tokenAMarketCap + tokenBMarketCap);

        uint256 stablecoinToInvest = stablecoinAmount - mintFee;
        uint256 amountToInvestInTokenA = (stablecoinToInvest *
            tokenAIndexShare) / 100;
        uint256 amountToInvestInTokenB = stablecoinToInvest -
            amountToInvestInTokenA;

        TokenData memory tokenAData = tokenTickerToTokenData[tokenATicker];
        TokenData memory tokenBData = tokenTickerToTokenData[tokenBTicker];

        uint256 tokenAAmount = _swap(
            address(stablecoin),
            address(tokenAData.token),
            amountToInvestInTokenA,
            3000
        );
        uint256 tokenBAmount = _swap(
            address(stablecoin),
            address(tokenBData.token),
            amountToInvestInTokenB,
            3000
        );

        userToUserData[msg.sender].tokenAAmount += tokenAAmount;
        userToUserData[msg.sender].tokenBAmount += tokenBAmount;

        uint256 sharesToMint = stablecoinToInvest / mintPrice;
        userToUserData[msg.sender].mintedShares += sharesToMint;
        psvToken.mint(msg.sender, sharesToMint);
    }

    // function rebalance();

    function burnShare(
        uint256 amount
    )
        public
        allowanceChecker(address(psvToken), msg.sender, address(this), amount)
    {
        UserData memory userData = userToUserData[msg.sender];
        uint256 userMintedShares = userData.mintedShares;
        require(amount <= userMintedShares, "Amount too big");

        uint256 sharesBurnedProportion = (amount * 100) / userMintedShares;
        uint256 tokenAToSwap = (userData.tokenAAmount *
            sharesBurnedProportion) / 100;
        uint256 tokenBToSwap = (userData.tokenBAmount *
            sharesBurnedProportion) / 100;

        TokenData memory stablecoinData = tokenTickerToTokenData[
            stablecoinTicker
        ];
        TokenData memory tokenAData = tokenTickerToTokenData[tokenATicker];
        TokenData memory tokenBData = tokenTickerToTokenData[tokenBTicker];

        IERC20 stablecoin = stablecoinData.token;

        uint256 stablecoinToSend = _swap(
            address(tokenAData.token),
            address(stablecoin),
            tokenAToSwap,
            3000
        ) +
            _swap(
                address(tokenBData.token),
                address(stablecoin),
                tokenBToSwap,
                3000
            );

        userToUserData[msg.sender].mintedShares -= amount;
        psvToken.burn(msg.sender, amount);
        stablecoin.transfer(msg.sender, stablecoinToSend);
    }

    function _swap(
        address tokenA,
        address tokenB,
        uint256 amountIn,
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
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function _getTokenPrice(
        AggregatorV3Interface tokenDataFeed
    ) internal view returns (uint256) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = tokenDataFeed.latestRoundData();
        return uint256(answer);
    }

    function _computeTokenMarketCap(
        string memory tokenTicker
    ) internal view returns (uint256) {
        bytes32 tokenTicketHash = keccak256(abi.encodePacked(tokenTicker));
        require(
            tokenTicketHash == keccak256(abi.encodePacked(tokenATicker)) ||
                tokenTicketHash == keccak256(abi.encodePacked(tokenBTicker)) ||
                tokenTicketHash ==
                keccak256(abi.encodePacked(stablecoinTicker)),
            "Wrong ticker!"
        );
        if (tokenTicketHash == keccak256(abi.encodePacked("WBTC"))) {
            return
                _getTokenPrice(
                    tokenTickerToTokenData["WBTC"].priceDataFetcher
                ) * 21_000_000;
        } else if (tokenTicketHash == keccak256(abi.encodePacked("ETH"))) {
            return
                _getTokenPrice(tokenTickerToTokenData["ETH"].priceDataFetcher) *
                120_450_000;
        }
        TokenData memory data = tokenTickerToTokenData[tokenTicker];
        uint256 price = _getTokenPrice(data.priceDataFetcher);
        IERC20 token = data.token;
        return price * token.totalSupply();
    }
}
