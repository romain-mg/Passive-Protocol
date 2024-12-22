// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.7;
pragma abicoder v2;

import "./TransferHelper.sol";
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
    mapping(address => UserData) user_to_user_data;

    mapping(string => bytes32) token_name_to_price_id;
    mapping(string => IERC20) token_name_to_token;

    uint256 mintFeeBalance;

    uint256 public immutable mintPrice = 1;

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    IERC20 public immutable stablecoin;
    IERC20 public psv;

    string tokenAName;
    string tokenBName;

    AggregatorV3Interface internal tokenADataFeed;
    AggregatorV3Interface internal tokenBDataFeed;

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
        address _pyth,
        bytes32 _tokenBUsdPriceId,
        bytes32 _tokenAUsdPriceId,
        bytes32 _stablecoinUsdPriceId,
        IERC20 _tokenA,
        IERC20 _tokenB,
        string _tokenAName,
        string _tokenBName,
        IERC20 _stablecoin,
        IERC20 _psv,
        address _tokenADataFeed,
        address _tokenBDataFeed
    ) {
        swapRouter = _swapRouter;
        pyth = IPyth(_pyth);
        tokenAUsdPriceId = _tokenAUsdPriceId;
        tokenBUsdPriceId = _tokenBUsdPriceId;
        stablecoinUsdPriceId = _stablecoinUsdPriceId;

        tokenA = _tokenA;
        tokenB = _tokenB;
        tokenAName = _tokenAName;
        tokenBName = _tokenBName;
        stablecoin = _stablecoin;
        psv = _psv;

        token_name_to_price_id[tokenAName] = tokenAUsdPriceId;
        token_name_to_price_id[tokenBName] = tokenBUsdPriceId;
        token_name_to_price_id["stablecoin"] = stablecoinUsdPriceId;

        token_name_to_token[tokenAName] = tokenA;
        token_name_to_token[tokenBName] = tokenB;
        token_name_to_token["stablecoin"] = stablecoin;

        tokenADataFeed = AggregatorV3Interface(_tokenADataFeed);
        tokenBDataFeed = AggregatorV3Interface(_tokenBDataFeed);
    }

    function fetchPrice(string memory tokenName) public view returns (uint256) {
        bytes32 priceId = token_name_to_price_id[tokenName];

        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceId, 60);

        uint price18Decimals = (uint(uint64(price.price)) * (10 ** 18)) /
            (10 ** uint8(uint32(-1 * price.expo)));
        console.log(price18Decimals);
        return price18Decimals;
    }

    function computeIERC20MarketCap(
        string memory tokenName
    ) public view returns (uint256) {
        if (tokenName == "WBTC") {
            return fetchPrice("WBTC") * 21000000;
        }
        uint256 price = fetchPrice(tokenName);
        IERC20 token = token_name_to_token[tokenName];
        return price * token.totalSupply();
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

        uint256 tokenAMarketCap = computeIERC20MarketCap(tokenAName);
        uint256 tokenBMarketCap = computeIERC20MarketCap(tokenBName);

        uint256 totalMarketCap = tokenAMarketCap + tokenBMarketCap;
        uint256 tokenAIndexShare = tokenAMarketCap / totalMarketCap;

        uint256 stablecoinToInvest = stablecoinAmount - mint_fee;
        uint256 amountToInvestInTokenA = stablecoinToInvest * tokenAIndexShare;
        uint256 amountToInvestInTokenB = stablecoinToInvest -
            amountToInvestInTokenA;

        uint256 tokenAAmount = swap(
            address(stablecoin),
            address(tokenA),
            amountToInvestInTokenA,
            3000
        );
        uint256 tokenBAmount = swap(
            address(stablecoin),
            address(tokenB),
            amountToInvestInTokenB,
            3000
        );

        user_to_user_data[msg.sender].tokenAAmount += tokenAAmount;
        user_to_user_data[msg.sender].tokenBAmount += tokenBAmount;

        uint256 sharesToMint = stablecoinToInvest / mintPrice;
        user_to_user_data[msg.sender].mintedShares += sharesToMint;
        psv.mint(msg.sender, sharesToMint);
    }

    // function rebalance();

    function burnShare(
        uint256 amount
    ) allowanceChecker(psv, msg.sender, address(this), amount) {
        UserData userData = userToUserData[msg.sender];
        uint256 sharesBurnedProportion = (amount * 100) / userData.mintedShares;

        uint256 tokenAToSwap = (userData.tokenAAmount * 100) /
            sharesBurnedProportion;
        uint256 tokenBToSwap = (userData.tokenBAmount * 100) /
            sharesBurnedProportion;
        uint256 stablecoinToSend = swap(tokenA, stablecoin, tokenAToSwap) +
            swap(tokenB, stablecoin, tokenBToSwap);

        user_to_user_data[msg.sender].mintedShares -= amount / mintPrice;
        psv.burn(msg.sender, amount);
        stablecoin.transfer(msg.sender, stablecoinToSend);
    }

    function swap(
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
}
