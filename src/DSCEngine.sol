// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import { AggregatorV3Interface } from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { DecentralizedStableCoin } from './DecentralizedStableCoin.sol';

/*
 * @title: the engine to keep DSC pegged to USD using wETH as collateral.
 * @author: David Vu based on Pattric Collins work
 * @notice:
 * - Pegging 1 DSC = $1 USD
 * - OverCollateral: At no point, should the value of DSC >= the value of back collateral
 * - Exogenous : algorithmically stable
 */

contract DSCEngine is ReentrancyGuard {
    /////////////////////////////////////////////
    //                 Errors                  //
    /////////////////////////////////////////////
    error DSCEngine__MustNotEmpty();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__DepositFailed();
    error DSCEngine__BreakHealthFactor(uint256);
    error DSCEngine__MintFailed();
    error DSCEngine__TransferFailed();
    error DSCEngine__RedeemAmountOverDeposit();
    error DSCEngine__OutOfBalance();
    error DSCEngine__NotLiquidateHealthFactorOk();
    error DSCEngine__OutOfMintedAmount(address, uint256);
    error DSCEngine__Test(address, uint256);
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /////////////////////////////////////////////
    //            Type declarations            //
    /////////////////////////////////////////////

    /////////////////////////////////////////////
    //          State varriables               //
    /////////////////////////////////////////////
    uint256 private constant USD_PRECISION = 1e8;
    uint256 private constant COLLATERAL_PRECISION = 1e18;

    uint256 private constant PERCENT_PRECISION = 100;
    uint256 private constant COLLATERALIZED_PERCENT = 200; // 200% overcollateralized or 02 collateral value (in usd) back 01 DSC
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%

    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    DecentralizedStableCoin private immutable i_dsc;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;
    address[] private s_collateralTokens;

    /////////////////////////////////////////////
    //                    Events               //
    /////////////////////////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    /////////////////////////////////////////////
    //              Modifier                   //
    /////////////////////////////////////////////

    modifier moreThanZero(uint256 amount) {
        _moreThanZero(amount);
        _;
    }

    modifier isAllowedToken(address token) {
        _isAllowToken(token);
        _;
    }

    /////////////////////////////////////////////
    //              Functions                  //
    /////////////////////////////////////////////

    /*
     *
     * @param tokenAddreses :
     * @param priceFeedAddreses : Price feed address,use USD price feed susch as ETH/USD, BTC/USD...
     * @param dscAddress: Decentralized Stable Coin address
     */
    constructor(address[] memory tokenAddreses, address[] memory priceFeedAddreses, address dscAddress) {
        if (tokenAddreses.length == 0) {
            revert DSCEngine__MustNotEmpty();
        }
        if (tokenAddreses.length != priceFeedAddreses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddreses.length; i++) {
            s_priceFeeds[tokenAddreses[i]] = priceFeedAddreses[i];
            s_collateralTokens.push(tokenAddreses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////////////////////////
    //         External functions              //
    /////////////////////////////////////////////

    /**
     * Deposit collateral and mint DSC in the same transaction
     * @param tokenCollateralAddress : the token address to deposit as collateral
     * @param amountCollateral: the amount of collateral to deposit
     * @param amountDscToMint: the amount of DSC to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @notes follows CEI (Check Effect Interraction) pattern in smart contract security
     * @param tokenCollateralAddress : the address of the token deposited as collateral
     * @param amountCollateral : the amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant isAllowedToken(tokenCollateralAddress) {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (success == false) {
            revert DSCEngine__DepositFailed();
        }
    }

    /*
     * This function burn the DSC then return the underling collaterals in one transaction
     * @param tokenCollateralAddress : the collateral address to redeem
     * @param amountCollateral : the amount of collateral to return
     * @param amountDscToBurn  : the amount of DSC to burn
     * @notes: how if the burn value is lower the redeem value.
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        //First,burn the DSC then return the collaterals
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /*
     * Return collateral to user
     * @param tokenCollateralAddress: address of collateral token
     * @param amountCollateral: amount of collateral token
     * @notes Ensure health factor is over 1 AFTER the redeem
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        // Check health factor after the transfer, revert the transaction if HF <1
        _revertIfHealthFactorBroken(msg.sender);
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // revert if they are minted too much / the minted amount value will excess collateral value
        _revertIfHealthFactorBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, amountDscToMint);
        if (success == false) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amountDsc) public moreThanZero(amountDsc) nonReentrant {
        _burnDsc(amountDsc, msg.sender, msg.sender);
        // not neccessary: never hit
        //_revertIfHealthFactorBroken(msg.sender);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /*
     * @param collateralToken: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(
        address collateralToken,
        address user,
        uint256 debtToCover
    ) external isAllowedToken(collateralToken) moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // If covering 100 DSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / PERCENT_PRECISION;
        // Burn DSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(collateralToken, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        //uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        // if (endingUserHealthFactor <= startingUserHealthFactor) {
        //     revert DSCEngine__HealthFactorNotImproved();
        // }
        _revertIfHealthFactorBroken(msg.sender);
    }

    /////////////////////////////////////////////
    //     Internal and private functions      //
    /////////////////////////////////////////////

    function _moreThanZero(uint256 amount) internal pure {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
    }

    function _isAllowToken(address token) internal view {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
    }

    function _getAccountInformation(
        address user
    ) private view returns (uint256 totalDscMinted, uint256 collateralInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralInUsd = getAccountCollateralValueInUsd(user);
    }

    // Return price with USD_PRECISION
    function _getPriceInUsd(address collateralToken) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    /*
     * Returns how close to liquidation a user is.
     * If a user goes bellow 1, he can be get liquidated
     * @param user : address of user
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalMinted, uint256 totalCollateralInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalMinted, totalCollateralInUsd);
    }

    function _calculateHealthFactor(uint256 totalMinted, uint256 totalCollateralInUsd) internal pure returns (uint256) {
        uint256 adjustedCollateral = (totalCollateralInUsd * PERCENT_PRECISION) / COLLATERALIZED_PERCENT;
        if (totalMinted == 0) return type(uint256).max;
        return ((adjustedCollateral * COLLATERAL_PRECISION) / totalMinted);
    }

    /*
     * 1 - Check health factor (do they have enough collaterals?)
     * 2 - Revert if they do not
     * @param user : address of user
     */
    function _revertIfHealthFactorBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreakHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        // Check if the redeem amount is over the deposit ??
        if (s_collateralDeposited[msg.sender][tokenCollateralAddress] < amountCollateral) {
            revert DSCEngine__RedeemAmountOverDeposit();
        }
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        if (s_DSCMinted[onBehalfOf] < amountDscToBurn) {
            revert DSCEngine__OutOfMintedAmount(onBehalfOf, s_DSCMinted[onBehalfOf]);
        }
        s_DSCMinted[onBehalfOf] = s_DSCMinted[onBehalfOf] - amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    /////////////////////////////////////////////
    //            Public functions             //
    /////////////////////////////////////////////

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralInUsd) {
        totalCollateralInUsd = 0;
        for (uint i = 0; i < s_collateralTokens.length; i++) {
            totalCollateralInUsd += getUsdValue(
                s_collateralTokens[i],
                s_collateralDeposited[user][s_collateralTokens[i]]
            );
        }
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        uint256 price = _getPriceInUsd(token);
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        //return usdAmountInWei / uint256(price);
        //return uint256(price);
        return ((usdAmountInWei * USD_PRECISION) / price);
    }

    /**
     * Return USD amount of the collateral (weth, wbtc..)
     * @param token : collateral token address
     * @param amount : in terms of WEI (1e18)
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256 usdAmount) {
        // If 1 ETH = 1000 USD, the returned value from Chainlink will be 1000 * 1e8 (USD_PRECISION)
        uint256 price = _getPriceInUsd(token);
        return (price * amount) / USD_PRECISION;
    }

    function getAccountInformation(address user) public view returns (uint256 totalDscMinted, uint256 collateralInUsd) {
        return _getAccountInformation(user);
    }

    function calculateHealthFactor(uint256 totalMinted, uint256 totalCollateralInUsd) public pure returns (uint256) {
        return _calculateHealthFactor(totalMinted, totalCollateralInUsd);
    }

    // In 100
    function getCollateralizedPercent() public pure returns (uint256) {
        return COLLATERALIZED_PERCENT;
    }

    function getLiquidationBonusPercent() public pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getAccountCollateral(address collateral, address user) public view returns (uint256) {
        return s_collateralDeposited[user][collateral];
    }
}
