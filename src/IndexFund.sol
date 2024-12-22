// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.7;
pragma abicoder v2;

import "@v3-periphery/libraries/TransferHelper.sol";
import "@v3-periphery/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IndexFund {
    ISwapRouter public immutable swapRouter;

    IPyth pyth;
    bytes32 tokenAUsdPriceId;
    bytes32 tokenBUsdPriceId;
    bytes32 stablecoinUsdPriceId;

    mapping(address => uint256) user_to_minted_shares;

    mapping(string => bytes32) token_name_to_price_id;

    mapping(string => IERC20) token_name_to_token;

    uint256 rebalancing_fee_balance;

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    IERC20 public immutable stablecoin;
    IERC20 public psv;

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

    constructor(
        ISwapRouter _swapRouter,
        address _pyth,
        bytes32 _tokenBUsdPriceId,
        bytes32 _tokenAUsdPriceId,
        bytes32 _stablecoinUsdPriceId,
        IERC20 _tokenA,
        IERC20 _tokenB,
        IERC20 _stablecoin,
        IERC20 _psv
    ) {
        swapRouter = _swapRouter;
        pyth = IPyth(_pyth);
        tokenAUsdPriceId = _tokenAUsdPriceId;
        tokenBUsdPriceId = _tokenBUsdPriceId;
        stablecoinUsdPriceId = _stablecoinUsdPriceId;

        tokenA = _tokenA;
        tokenB = _tokenB;
        stablecoin = _stablecoin;
        psv = _psv;

        token_name_to_price_id["tokenA"] = tokenAUsdPriceId;
        token_name_to_price_id["tokenB"] = tokenBUsdPriceId;
        token_name_to_price_id["stablecoin"] = stablecoinUsdPriceId;

        token_name_to_token["tokenA"] = tokenA;
        token_name_to_token["tokenB"] = tokenB;
        token_name_to_token["stablecoin"] = stablecoin;
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
        uint256 price = fetchPrice(tokenName);
        IERC20 token = token_name_to_token[tokenName];
        return price * token.totalSupply();
    }

    function mintShare(uint256 stablecoinAmount) public {
        require(stablecoinAmount > 0, "You need to provide some stablecoin");
        uint256 allowance = stablecoin.allowance(msg.sender, address(this));
        require(allowance >= stablecoinAmount, "Check the token allowance");
        stablecoin.transferFrom(msg.sender, address(this), stablecoinAmount);
        uint256 rebalancing_fee_share = stablecoinAmount / 1000;

        uint256 tokenAMarketCap = computeIERC20MarketCap("tokenA");
        uint256 tokenBMarketCap = computeIERC20MarketCap("tokenB");

        uint256 totalMarketCap = tokenAMarketCap + tokenBMarketCap;
        uint256 tokenAIndexShare = tokenAMarketCap / totalMarketCap;

        uint256 stablecoinToInvest = stablecoinAmount - rebalancing_fee_share;
        uint256 amountToInvestInTokenA = stablecoinToInvest * tokenAIndexShare;
        uint256 amountToInvestInTokenB = stablecoinToInvest -
            amountToInvestInTokenA;

        swap(
            address(stablecoin),
            address(tokenA),
            amountToInvestInTokenA,
            3000
        );
        swap(
            address(stablecoin),
            address(tokenA),
            amountToInvestInTokenB,
            3000
        );
    }

    // function burnShare(uint256 amount);

    // function rebalance();

    function swap(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint24 poolFee
    ) private returns (uint256 amountOut) {
        TransferHelper.safeTransferFrom(
            tokenA,
            msg.sender,
            address(this),
            amountIn
        );
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
