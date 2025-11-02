// SPDX-License-Identicator:MIT
pragma solidity ^0.8.18;

import { Test } from 'forge-std/Test.sol';
import { console2 } from 'forge-std/Script.sol';
import { DeployDSC } from '../../script/DeployDSC.s.sol';
import { HelperConfig, CodeConstants } from '../../script/HelperConfig.s.sol';
import { DSCEngine } from '../../src/DSCEngine.sol';
import { DecentralizedStableCoin } from '../../src/DecentralizedStableCoin.sol';
import { ERC20Mock } from '@openzeppelin/contracts/mocks/ERC20Mock.sol';

contract DSEngineTest is CodeConstants, Test {
    constructor() {}

    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dscCoin;
    address USER = makeAddr('user');
    uint256 constant AMOUNT_COLLATERAL = 10 ether;
    uint256 constant STARTING_BALANCE = 50 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    function setUp() public {
        deployer = new DeployDSC();
        (dscCoin, dscEngine, helperConfig) = deployer.run();
        config = helperConfig.getConfig();

        //Provide USER some money to test
        if (block.chainid == LOCAL_CHAIN_ID) {
            ERC20Mock(config.wEth).mint(USER, STARTING_BALANCE);
        }
    }

    /////////////////////////////////////////////
    //            Library
    /////////////////////////////////////////////
    function getPriceInUsd(address collateralToken) public view returns (uint256) {
        return dscEngine.getUsdValue(collateralToken, 1) * 1e8;
    }

    function getMaxMintAmount(
        address collateralToken,
        uint256 collateralAmount
    ) private view returns (uint256 maxMintAmount) {
        uint256 priceInUsd = getPriceInUsd(collateralToken) / 1e8;
        uint256 collateralInUsd = (collateralAmount * priceInUsd);
        maxMintAmount = (collateralInUsd * dscEngine.getLiquidationThreshold()) / 100;
        // console2.log('------getMaxMintAmount-------');
        // console2.log('collateralAmount', collateralAmount);
        // console2.log('priceInUsd', priceInUsd);
        // console2.log('collateralInUsd', collateralInUsd);
    }

    /////////////////////////////////////////////
    //            Constructor tests
    /////////////////////////////////////////////
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testTokenAndPriceFeedAddresesMustBeTheSameLenght() public {
        tokenAddresses.push(config.wEth);
        tokenAddresses.push(config.wBtc);
        priceFeedAddresses.push(config.wEthPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dscCoin));
    }

    /////////////////////////////////////////////
    //              Price tests
    /////////////////////////////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15 ether;
        uint256 ethPriceInUsd = getPriceInUsd(config.wEth);
        uint256 actualAmount = dscEngine.getUsdValue(config.wEth, ethAmount);
        uint256 expectedAmount = (ethAmount * ethPriceInUsd) / 1e8;
        // console2.log("actualAmount", actualAmount);
        // console2.log("expectedAmount", expectedAmount);
        assertEq(actualAmount, expectedAmount);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 150 ether;
        uint256 actualAmount = dscEngine.getTokenAmountFromUsd(config.wEth, usdAmount);
        uint256 ethPriceInUsd = getPriceInUsd(config.wEth);
        uint256 expectedAmount = usdAmount / (ethPriceInUsd / 1e8);
        console2.log('actualAmount', actualAmount);
        console2.log('expectedAmount', expectedAmount);
        assertEq(actualAmount, expectedAmount);
    }

    /////////////////////////////////////////////
    //         Deposit collateral tests
    /////////////////////////////////////////////
    modifier depositCollateral(uint256 collateralAmount) {
        //ERC20Mock(config.wEth).mint(USER, collateralAmount);

        vm.startPrank(USER);
        ERC20Mock(config.wEth).approve(address(dscEngine), collateralAmount);
        dscEngine.depositCollateral(config.wEth, collateralAmount);
        vm.stopPrank();
        _;
    }

    function testRevertIfDepositUnApprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock('Random token', 'RAN', USER, AMOUNT_COLLATERAL);
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    function testRevertIfDepositZero() public {
        vm.prank(USER);
        ERC20Mock(config.wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(config.wEth, 0);
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositCollateral(STARTING_BALANCE) {
        (uint256 totalDscMinted, uint256 collateralInUsd) = dscEngine.getAccountInformation(USER);
        //console2.log("totalDscMinted", totalDscMinted);
        uint256 expectCollateralAmount = dscEngine.getTokenAmountFromUsd(config.wEth, collateralInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectCollateralAmount, STARTING_BALANCE);
    }

    function testCanDepositCollateralWithoutMinting() public depositCollateral(AMOUNT_COLLATERAL) {
        uint256 userBalance = dscCoin.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    /////////////////////////////////////////////
    //         Mint tests
    /////////////////////////////////////////////
    function testRevertsIfMintAmountIsZero() public depositCollateral(AMOUNT_COLLATERAL) {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertBigMintAmountFailed() public depositCollateral(AMOUNT_COLLATERAL) {
        uint256 mintAmount = getMaxMintAmount(config.wEth, AMOUNT_COLLATERAL) + 1;
        uint256 collateralInUsd = dscEngine.getUsdValue(config.wEth, AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(mintAmount, collateralInUsd);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, expectedHealthFactor));

        vm.prank(USER);
        dscEngine.mintDsc(mintAmount);
    }

    function testCanMintWithDepositedCollateral() public depositCollateral(AMOUNT_COLLATERAL) {
        uint256 amountToMint = getMaxMintAmount(config.wEth, AMOUNT_COLLATERAL);
        vm.prank(USER);
        dscEngine.mintDsc(amountToMint);

        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint);

        uint256 userBalance = dscCoin.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    function testCanMinWithDepositCollateralAndMintDsc() public {
        uint256 amountToMint = getMaxMintAmount(config.wEth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(config.wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(config.wEth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint);

        uint256 userBalance = dscCoin.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    //////////////////////////////////
    //      burnDsc Tests
    ///////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public depositCollateral(AMOUNT_COLLATERAL) {
        uint256 amountToMint = getMaxMintAmount(config.wEth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        dscEngine.mintDsc(amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testCannotBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDsc(1);
    }

    function testCanBurnDsc() public depositCollateral(AMOUNT_COLLATERAL) {
        uint256 amountToMint = getMaxMintAmount(config.wEth, AMOUNT_COLLATERAL);
        uint256 amountDscToRedeem = amountToMint - 1;
        vm.startPrank(USER);
        dscEngine.mintDsc(amountToMint);
        dscCoin.approve(address(dscEngine), amountToMint);

        dscEngine.burnDsc(amountDscToRedeem);
        vm.stopPrank();

        uint256 userBalance = dscCoin.balanceOf(USER);
        assertEq(userBalance, amountToMint - amountDscToRedeem);
    }

    ///////////////////////////////////
    //   Redeem Collateral Tests
    //////////////////////////////////

    // this test needs it's own setup
    // function testRevertsIfTransferFails() public {
    //     // Arrange - Setup
    //     address owner = msg.sender;
    //     vm.prank(owner);
    //     MockFailedTransfer mockDsc = new MockFailedTransfer();
    //     tokenAddresses = [address(mockDsc)];
    //     feedAddresses = [ethUsdPriceFeed];
    //     vm.prank(owner);
    //     DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
    //     mockDsc.mint(user, amountCollateral);

    //     vm.prank(owner);
    //     mockDsc.transferOwnership(address(mockDsce));
    //     // Arrange - User
    //     vm.startPrank(user);
    //     ERC20Mock(address(mockDsc)).approve(address(mockDsce), amountCollateral);
    //     // Act / Assert
    //     mockDsce.depositCollateral(address(mockDsc), amountCollateral);
    //     vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    //     mockDsce.redeemCollateral(address(mockDsc), amountCollateral);
    //     vm.stopPrank();
    // }

    function testRevertsIfRedeemAmountIsZero() public depositCollateral(AMOUNT_COLLATERAL) {
        uint256 amountToMint = getMaxMintAmount(config.wEth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        dscEngine.mintDsc(amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(config.wEth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositCollateral(AMOUNT_COLLATERAL) {
        vm.startPrank(USER);
        uint256 userBalanceBeforeRedeem = dscEngine.getCollateralBalanceOfUser(USER, config.wEth);
        assertEq(userBalanceBeforeRedeem, AMOUNT_COLLATERAL);
        dscEngine.redeemCollateral(config.wEth, AMOUNT_COLLATERAL);
        uint256 userBalanceAfterRedeem = dscEngine.getCollateralBalanceOfUser(USER, config.wEth);
        assertEq(userBalanceAfterRedeem, 0);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositCollateral(AMOUNT_COLLATERAL) {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(USER, USER, config.wEth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(config.wEth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanRedeemCollateralForDsc() public {
        uint256 amountToMint = getMaxMintAmount(config.wEth, AMOUNT_COLLATERAL);
        uint256 amountCollateralToRedeem = AMOUNT_COLLATERAL / 2;
        uint256 amountDscToRedeem = getMaxMintAmount(config.wEth, amountCollateralToRedeem);

        vm.startPrank(USER);
        ERC20Mock(config.wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(config.wEth, AMOUNT_COLLATERAL, amountToMint);
        dscCoin.approve(address(dscEngine), amountToMint);

        dscEngine.redeemCollateralForDsc(config.wEth, amountCollateralToRedeem, amountDscToRedeem);
        vm.stopPrank();

        uint256 collateralBalanceOfUser = dscEngine.getCollateralBalanceOfUser(USER, config.wEth);
        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(collateralBalanceOfUser, AMOUNT_COLLATERAL - amountCollateralToRedeem);
        assertEq(totalDscMinted, amountToMint - amountDscToRedeem);
    }

    /////////////////////////////////////////////
    //             Integration
    /////////////////////////////////////////////
    function testCanDepositAndMintAndRedeem() public depositCollateral(AMOUNT_COLLATERAL) {
        // Mint
        uint256 amountToMint = getMaxMintAmount(config.wEth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        dscEngine.mintDsc(amountToMint);
        dscCoin.approve(address(dscEngine), amountToMint);
        vm.stopPrank();

        //Burn
        uint256 needRedeemETH = 1;
        vm.startPrank(USER);
        uint256 amounToBurn = getMaxMintAmount(config.wEth, needRedeemETH);
        dscEngine.burnDsc(amounToBurn);
        vm.stopPrank();

        // Redeem
        uint userOpenETH = ERC20Mock(config.wEth).balanceOf(USER);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(config.wEth, needRedeemETH);
        vm.stopPrank();
        uint256 userCloseETH = ERC20Mock(config.wEth).balanceOf(USER);

        //Check
        assertEq(userCloseETH, userOpenETH + needRedeemETH);
        (uint256 remainMinted, uint256 remainCollateralInUsd) = dscEngine.getAccountInformation(USER);
        uint remainCollateral = dscEngine.getTokenAmountFromUsd(config.wEth, remainCollateralInUsd);
        assertEq(STARTING_BALANCE, userCloseETH + remainCollateral);
        assertEq(remainMinted, amountToMint - amounToBurn);
    }

    function testDepositCollateralAndMintDsc() public {
        uint256 amountToMint = getMaxMintAmount(config.wEth, AMOUNT_COLLATERAL);
        //Deposit and mint
        vm.startPrank(USER);
        ERC20Mock(config.wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(config.wEth, AMOUNT_COLLATERAL, amountToMint);
        dscCoin.approve(address(dscEngine), amountToMint);
        vm.stopPrank();

        //Burn
        uint256 needRedeemETH = 1;
        vm.startPrank(USER);
        uint256 amounToBurn = getMaxMintAmount(config.wEth, needRedeemETH);
        dscEngine.burnDsc(amounToBurn);
        vm.stopPrank();

        // Redeem
        uint userOpenETH = ERC20Mock(config.wEth).balanceOf(USER);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(config.wEth, needRedeemETH);
        vm.stopPrank();
        uint256 userCloseETH = ERC20Mock(config.wEth).balanceOf(USER);

        //Check
        console2.log('STARTING_BALANCE', STARTING_BALANCE);
        console2.log('userOpenETH', userOpenETH);
        console2.log('userCloseETH', userCloseETH);

        assertEq(userCloseETH, userOpenETH + needRedeemETH);

        (uint256 remainMinted, uint256 remainCollateralInUsd) = dscEngine.getAccountInformation(USER);
        uint remainCollateral = dscEngine.getTokenAmountFromUsd(config.wEth, remainCollateralInUsd);
        assertEq(STARTING_BALANCE, userCloseETH + remainCollateral);
        assertEq(remainMinted, amountToMint - amounToBurn);
    }

    /////////////////////////////////////////////
    //             Health factor
    /////////////////////////////////////////////
    function testGetHealthFactor() public depositCollateral(AMOUNT_COLLATERAL) {
        // Mint
        uint256 amountToMint = getMaxMintAmount(config.wEth, 1);
        vm.startPrank(USER);
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
        (uint256 totalMinted, uint256 totalCollateralInUsd) = dscEngine.getAccountInformation(USER);
        uint actualHealthFactor = dscEngine.getHealthFactor(USER);
        uint expectedHealthFactor = dscEngine.calculateHealthFactor(totalMinted, totalCollateralInUsd);
        assertEq(actualHealthFactor, expectedHealthFactor);
    }
}
