// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.7;
pragma abicoder v2;

import "../helpers/TransferHelper.sol";
import "@v3-periphery/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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

    IERC20 public psv;

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
    }

    constructor(
        ISwapRouter _swapRouter,
        address _tokenA,
        address _tokenB,
        address _stablecoin,
        string _tokenATicker,
        string _tokenBTicker,
        string _stablecoinTicker
        address _psv,
        address _tokenADataFeed,
        address _tokenBDataFeed
        address _stablecoinDataFeed
    ) {
        swapRouter = _swapRouter;

        tokenATicker = _tokenATicker;
        tokenBTicker = _tokenBTicker;
        stablecoinTicker = _stablecoinTicker;

        tokenTickerToTokenData[tokenATicker].token = IERC20(_tokenA);
        tokenTickerToTokenData[tokenATicker].priceDataFetcher = AggregatorV3Interface(_tokenADataFeed);
        tokenTickerToTokenData[tokenBTicker].token = IERC20(_tokenB);
        tokenTickerToTokenData[tokenBTicker].priceDataFetcher = AggregatorV3Interface(_tokenBDataFeed);
        tokenTickerToTokenData[stablecoinTicker].token = IERC20(_stablecoin);
        tokenTickerToTokenData[stablecoinTicker].priceDataFetcher = AggregatorV3Interface(_stablecoinDataFeed);
    }

    function mintShare(
        uint256 stablecoinAmount
    )
        public
        allowanceChecker(
            stablecoin,
            msg.sender,
            address(this),
            stablecoinAmount
        )
        nonReentrant
    {
        require(stablecoinAmount > 0, "You need to provide some stablecoin");
        stablecoin.transferFrom(msg.sender, address(this), stablecoinAmount);

        uint256 mint_fee = stablecoinAmount / 1000;
        mintFeeBalance += mint_fee;

        uint256 tokenAMarketCap = _computeTokenMarketCap(tokenATicker);
        uint256 tokenBMarketCap = _computeTokenMarketCap(tokenBTicker);

        uint256 tokenAIndexShare = (tokenAMarketCap + tokenBMarketCap) * 100 / totalMarketCap;

        uint256 stablecoinToInvest = stablecoinAmount - mint_fee;
        uint256 amountToInvestInTokenA = stablecoinToInvest * tokenAIndexShare / 100;
        uint256 amountToInvestInTokenB = stablecoinToInvest -
            amountToInvestInTokenA;

        uint256 tokenAAmount = _swap(
            address(stablecoin),
            address(tokenA),
            amountToInvestInTokenA,
            3000
        );
        uint256 tokenBAmount = _swap(
            address(stablecoin),
            address(tokenB),
            amountToInvestInTokenB,
            3000
        );

        userToUserData[msg.sender].tokenAAmount += tokenAAmount;
        userToUserData[msg.sender].tokenBAmount += tokenBAmount;

        uint256 sharesToMint = stablecoinToInvest / mintPrice;
        userToUserData[msg.sender].mintedShares += sharesToMint;
        psv.mint(msg.sender, sharesToMint);
    }

    // function rebalance();

    function burnShare(
        uint256 amount
    ) allowanceChecker(psv, msg.sender, address(this), amount) {
        
        UserData userData = userToUserData[msg.sender];
        uint256 userMintedShares = userData.mintedShares;
        require(amount <= userMintedShares, "Amount too big");

        uint256 sharesBurnedProportion = (amount * 100) / userMintedShares;
        uint256 tokenAToSwap = (userData.tokenAAmount * sharesBurnedProportion) /
            100;
        uint256 tokenBToSwap = (userData.tokenBAmount * sharesBurnedProportion) /
            100;
        uint256 stablecoinToSend = _swap(tokenA, stablecoin, tokenAToSwap) +
            _swap(tokenB, stablecoin, tokenBToSwap);

        userToUserData[msg.sender].mintedShares -= amount;
        psv.burn(msg.sender, amount);
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
    ) internal view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = tokenDataFeed.latestRoundData();
        return answer;
    }

    function _computeTokenMarketCap(
        string memory tokenTicker
    ) internal view returns (uint256) {
        require(tokenTicker == tokenATicker || tokenTicker == tokenBTicker || tokenTicker == stablecoinTicker, "Wrong ticker!");
        if (tokenTicker == "WBTC") {
            return _getTokenPrice("WBTC") * 21000000;
        }
        // Need to do the ETH case
        TokenData data = tokenTickerToTokenData[tokenTicker]
        uint256 price = _getTokenPrice(data.priceDataFetcher);
        IERC20 token = data.tokenAddress;
        return price * token.totalSupply();
    }
}
