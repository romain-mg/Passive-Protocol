// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma abicoder v2;

import "@uniswap-v3-periphery-1.4.4/libraries/TransferHelper.sol";
import "@uniswap-v3-periphery-1.4.4/interfaces/ISwapRouter.sol";
import "@openzeppelin-contracts-5.2.0-rc.1/utils/ReentrancyGuard.sol";
import "@openzeppelin-contracts-5.2.0-rc.1/access/Ownable.sol";
import "@chainlink-contracts-1.3.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IIndexFund.sol";
import "../lib/TokenDataFetcher.sol";
import "./PSVToken.sol";

contract IndexFund is IIndexFund, ReentrancyGuard, Ownable {
    ISwapRouter public immutable swapRouter;

    struct UserData {
        uint256 mintedShares;
        uint256 tokenAAmount;
        uint256 tokenBAmount;
    }

    mapping(bytes32 => address) public tokenTickerToToken;
    mapping(address => UserData) public userToUserData;

    uint256 public immutable mintPrice;
    uint256 public immutable mintFeeDivisor;
    uint24 public immutable uniswapPoolFee;

    PSVToken public psvToken;

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

    constructor(
        address _swapRouter,
        address _tokenA,
        address _tokenB,
        address _stablecoin,
        bytes32 _tokenATicker,
        bytes32 _tokenBTicker,
        bytes32 _stablecoinTicker,
        address _psv,
        uint256 _mintPrice,
        uint256 _mintFeeDivisor,
        uint24 _uniswapPoolFee
    ) Ownable(msg.sender) {
        swapRouter = ISwapRouter(_swapRouter);

        tokenATicker = _tokenATicker;
        tokenBTicker = _tokenBTicker;
        stablecoinTicker = _stablecoinTicker;

        tokenTickerToToken[tokenATicker] = _tokenA;
        tokenTickerToToken[tokenBTicker] = _tokenB;
        tokenTickerToToken[stablecoinTicker] = _stablecoin;

        psvToken = PSVToken(_psv);

        TransferHelper.safeApprove(
            _tokenA,
            address(swapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            _tokenB,
            address(swapRouter),
            type(uint256).max
        );

        TransferHelper.safeApprove(
            _stablecoin,
            address(swapRouter),
            type(uint256).max
        );

        mintPrice = _mintPrice;
        mintFeeDivisor = _mintFeeDivisor;
        uniswapPoolFee = _uniswapPoolFee;
    }

    function mintShare(
        uint256 stablecoinAmount,
        uint256 tokenAPrice,
        uint256 tokenBPrice
    ) public nonReentrant {
        require(stablecoinAmount > 0, "You need to provide some stablecoin");

        IERC20 stablecoin = IERC20(tokenTickerToToken[stablecoinTicker]);

        require(
            stablecoin.balanceOf(msg.sender) >= stablecoinAmount,
            "Not enough stablecoin in user wallet"
        );
        require(
            stablecoin.allowance(msg.sender, address(this)) >= stablecoinAmount,
            "Allowance too small"
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
        ) = _investUserStablecoin(
                stablecoin,
                stablecoinAmount,
                tokenAPrice,
                tokenBPrice
            );

        uint256 sharesToMint = stablecoinToInvest / mintPrice;
        UserData storage userData = userToUserData[msg.sender];
        userData.mintedShares += sharesToMint;
        userData.tokenAAmount += tokenASwapped;
        userData.tokenBAmount += tokenBSwapped;

        psvToken.mint(msg.sender, sharesToMint);
        emit SharesMinted(msg.sender, sharesToMint, stablecoinAmount);
    }

    function burnShare(
        uint256 sharesToBurn,
        bool getBackIndexFundTokens,
        uint256 tokenAPrice,
        uint256 tokenBPrice
    ) public {
        require(
            psvToken.allowance(msg.sender, address(this)) >= sharesToBurn,
            "Allowance too small"
        );
        UserData storage userData = userToUserData[msg.sender];
        uint256 userMintedShares = userData.mintedShares;
        require(sharesToBurn <= userMintedShares, "Amount too big");

        if (getBackIndexFundTokens) {
            IERC20 tokenA = IERC20(tokenTickerToToken[tokenATicker]);
            IERC20 tokenB = IERC20(tokenTickerToToken[tokenBTicker]);
            uint256 tokenAToTransfer = (userData.tokenAAmount * sharesToBurn) /
                userMintedShares;
            uint256 tokenBToTransfer = (userData.tokenBAmount * sharesToBurn) /
                userMintedShares;
            userData.tokenAAmount -= tokenAToTransfer;
            userData.tokenBAmount -= tokenBToTransfer;
            userData.mintedShares -= sharesToBurn;
            bool tokenATransferSuccess = tokenA.transfer(
                msg.sender,
                tokenAToTransfer
            );
            require(
                tokenATransferSuccess,
                "Failed to transfer token A to user wallet"
            );

            bool tokenBTransferSuccess = tokenB.transfer(
                msg.sender,
                tokenBToTransfer
            );
            require(
                tokenBTransferSuccess,
                "Failed to transfer token B to user wallet"
            );
        } else {
            IERC20 stablecoin = IERC20(tokenTickerToToken[stablecoinTicker]);

            (
                uint256 stablecoinToSend,
                uint256 tokenASwapped,
                uint256 tokenBSwapped
            ) = _redeemUserStablecoin(
                    stablecoin,
                    userMintedShares,
                    sharesToBurn,
                    userData,
                    tokenAPrice,
                    tokenBPrice
                );
            userData.tokenAAmount -= tokenASwapped;
            userData.tokenBAmount -= tokenBSwapped;
            userData.mintedShares -= sharesToBurn;
            bool transferSuccess = stablecoin.transfer(
                msg.sender,
                stablecoinToSend
            );
            require(
                transferSuccess,
                "Failed to transfer stablecoin to user wallet"
            );
        }

        psvToken.burnFrom(msg.sender, sharesToBurn);

        emit SharesBurned(msg.sender, sharesToBurn);
    }

    function _investUserStablecoin(
        IERC20 stablecoin,
        uint256 stablecoinAmount,
        uint256 tokenAPrice,
        uint256 tokenBPrice
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

        (
            uint256 amountToInvestInTokenA,
            uint256 amountToInvestInTokenB
        ) = _computeTokenSwapInfoWhenMint(
                stablecoinInvested,
                tokenAPrice,
                tokenBPrice
            );

        address tokenAAddress = address(tokenTickerToToken[tokenATicker]);
        address tokenBAddress = address(tokenTickerToToken[tokenBTicker]);

        tokenAAmount = _swap(
            address(stablecoin),
            tokenAAddress,
            amountToInvestInTokenA,
            amountToInvestInTokenA / tokenAPrice / 2,
            uniswapPoolFee
        );
        tokenBAmount = _swap(
            address(stablecoin),
            tokenBAddress,
            amountToInvestInTokenB,
            amountToInvestInTokenB / tokenBPrice / 2,
            uniswapPoolFee
        );
    }

    function _redeemUserStablecoin(
        IERC20 stablecoin,
        uint256 userMintedShares,
        uint256 sharesToBurn,
        UserData memory userData,
        uint256 tokenAPrice,
        uint256 tokenBPrice
    )
        internal
        returns (
            uint256 stablecoinRedeemed,
            uint256 tokenASold,
            uint256 tokenBSold
        )
    {
        uint256 tokenAToSell = (userData.tokenAAmount * sharesToBurn) /
            userMintedShares;
        uint256 tokenBToSell = (userData.tokenBAmount * sharesToBurn) /
            userMintedShares;

        uint256 minimumStablecoinOutputA = (tokenAToSell * tokenAPrice) / 2;
        uint256 minimumStablecoinOutputB = (tokenBToSell * tokenBPrice) / 2;

        IERC20 tokenA = IERC20(tokenTickerToToken[tokenATicker]);
        IERC20 tokenB = IERC20(tokenTickerToToken[tokenBTicker]);

        uint256 redemmedStablecoin = _swap(
            address(tokenA),
            address(stablecoin),
            tokenAToSell,
            minimumStablecoinOutputA,
            uniswapPoolFee
        ) +
            _swap(
                address(tokenB),
                address(stablecoin),
                tokenBToSell,
                minimumStablecoinOutputB,
                uniswapPoolFee
            );

        return (redemmedStablecoin, tokenAToSell, tokenBToSell);
    }

    function _computeTokenSwapInfoWhenMint(
        uint256 stablecoinToInvest,
        uint256 tokenAPrice,
        uint256 tokenBPrice
    )
        internal
        view
        returns (uint256 amountToInvestInTokenA, uint256 amountToInvestInTokenB)
    {
        IERC20 tokenA = IERC20(tokenTickerToToken[tokenATicker]);
        IERC20 tokenB = IERC20(tokenTickerToToken[tokenBTicker]);

        uint256 tokenAMarketCap = TokenDataFetcher._getTokenMarketCap(
            uint256(tokenAPrice),
            tokenA,
            tokenATicker
        );
        uint256 tokenBMarketCap = TokenDataFetcher._getTokenMarketCap(
            uint256(tokenBPrice),
            tokenB,
            tokenBTicker
        );

        amountToInvestInTokenA =
            (stablecoinToInvest * tokenAMarketCap) /
            (tokenAMarketCap + tokenBMarketCap);
        amountToInvestInTokenB = stablecoinToInvest - amountToInvestInTokenA;
    }

    function _swap(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint24 poolFee
    ) private returns (uint256 amountOut) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenA,
                tokenOut: tokenB,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp + 300,
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
            IERC20(tokenTickerToToken[stablecoinTicker]).balanceOf(
                address(this)
            );
    }

    function getTokenBought(bytes32 ticker) public view returns (uint256) {
        return IERC20(tokenTickerToToken[ticker]).balanceOf(address(this));
    }

    function withdrawFees() public onlyOwner {
        IERC20 stablecoin = IERC20(tokenTickerToToken[stablecoinTicker]);
        bool transferSuccess = stablecoin.transfer(
            msg.sender,
            stablecoin.balanceOf(address(this))
        );
        require(transferSuccess, "Failed to transfer mint fees to owner");
    }
}
