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

    mapping(string => TokenData) public tokenTickerToTokenData;
    mapping(address => UserData) public userToUserData;

    uint256 public mintFeeBalance;
    uint256 public immutable mintPrice = 1;

    IPSVToken public psvToken;

    string tokenATicker;
    string tokenBTicker;
    string stablecoinTicker;

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
        emit FeeCollected(msg.sender, mintFee);

        uint256 tokenAMarketCap = _computeTokenMarketCap(tokenATicker);
        uint256 tokenBMarketCap = _computeTokenMarketCap(tokenBTicker);

        uint256 stablecoinToInvest = stablecoinAmount - mintFee;
        uint256 amountToInvestInTokenA = (stablecoinToInvest *
            tokenAMarketCap) / (tokenAMarketCap + tokenBMarketCap);
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

        emit SharesMinted(msg.sender, sharesToMint, stablecoinAmount);
    }

    function burnShare(
        uint256 amount
    )
        public
        allowanceChecker(address(psvToken), msg.sender, address(this), amount)
    {
        UserData memory userData = userToUserData[msg.sender];
        uint256 userMintedShares = userData.mintedShares;
        require(amount <= userMintedShares, "Amount too big");

        uint256 tokenAAmount = (userData.tokenAAmount * amount) /
            userMintedShares;
        uint256 tokenBAmount = (userData.tokenBAmount * amount) /
            userMintedShares;

        TokenData memory stablecoinData = tokenTickerToTokenData[
            stablecoinTicker
        ];
        TokenData memory tokenAData = tokenTickerToTokenData[tokenATicker];
        TokenData memory tokenBData = tokenTickerToTokenData[tokenBTicker];
        IERC20 stablecoin = stablecoinData.token;

        uint256 stablecoinToSend = _swap(
            address(tokenAData.token),
            address(stablecoin),
            tokenAAmount,
            3000
        ) +
            _swap(
                address(tokenBData.token),
                address(stablecoin),
                tokenBAmount,
                3000
            );

        userToUserData[msg.sender].mintedShares -= amount;
        userToUserData[msg.sender].tokenAAmount -= tokenAAmount;
        userToUserData[msg.sender].tokenBAmount -= tokenBAmount;

        psvToken.burn(msg.sender, amount);
        stablecoin.transfer(msg.sender, stablecoinToSend);
        emit SharesBurned(msg.sender, amount, stablecoinToSend);
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
        } else if (tokenTicketHash == keccak256(abi.encodePacked("WETH"))) {
            return
                _getTokenPrice(
                    tokenTickerToTokenData["WETH"].priceDataFetcher
                ) * 120_450_000;
        }
        TokenData memory data = tokenTickerToTokenData[tokenTicker];
        uint256 price = _getTokenPrice(data.priceDataFetcher);
        IERC20 token = data.token;
        return price * token.totalSupply();
    }

    function getUserData(
        address userAddress
    ) public returns (uint256, uint256, uint256) {
        UserData memory userData = userToUserData[userAddress];
        return (
            userData.mintedShares,
            userData.tokenAAmount,
            userData.tokenBAmount
        );
    }
}
