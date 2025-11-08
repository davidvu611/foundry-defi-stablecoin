// SPDX-License-Indicator:MIT
pragma solidity ^0.8.18;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { ERC20Mock } from '@openzeppelin/contracts/mocks/ERC20Mock.sol';
import { Test, console2 } from 'forge-std/Test.sol';
import { DSCEngine } from '../../src/DSCEngine.sol';
import { DecentralizedStableCoin } from '../../src/DecentralizedStableCoin.sol';
import { MockV3Aggregator } from '../mocks/MockV3Aggregator.sol';
import '../libraries/TestLib.sol';

contract Handler is Test {
    uint private constant MAX_DEPOSIT_AMOUNT = type(uint96).max;
    uint private constant PRICE_CHANGE_TIME_FRAME = 1 seconds;

    uint lastTimePriceChange;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    address[] collateralTokens;
    address[] haveDeposit;
    MockV3Aggregator ethUsdPriceFeed;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        collateralTokens = dsce.getCollateralTokens();
        ethUsdPriceFeed = MockV3Aggregator(dsce.getPriceFeed(collateralTokens[0]));
        lastTimePriceChange = block.timestamp;
    }

    function mint(uint8 seed, uint96 amount) public {
        if (haveDeposit.length == 0) {
            return;
        }
        address sender = haveDeposit[seed % haveDeposit.length];
        (uint totalMint, uint collateralInUsd) = dsce.getAccountInformation(sender);
        uint256 maxMintAmount = TestLib.getMaxMintFromUsd(dsce, collateralInUsd);
        if (maxMintAmount <= totalMint) {
            return;
        }
        maxMintAmount -= totalMint;
        uint amountMint = bound(amount, 0, maxMintAmount);
        if (amountMint == 0) {
            return;
        }
        _mint(sender, amountMint);
    }

    function depositCollateral(uint8 collateralSeed, uint40 amount) public {
        ERC20Mock collateral = _getCollateralAddress(collateralSeed);
        uint amountCollateral = bound(amount, 1, MAX_DEPOSIT_AMOUNT);
        _depositCollateral(msg.sender, collateral, amountCollateral);
    }

    function redeemCollateral(uint collateralSeed, uint amount) public {
        ERC20Mock collateral = _getCollateralAddress(collateralSeed);
        uint maxCollateralAmount = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
        uint amountCollateral = bound(amount, 0, maxCollateralAmount);
        //uint amountCollateral = bound(amount, 0, MAX_DEPOSIT_AMOUNT);
        if (amountCollateral <= 0) {
            return;
        }
        // console2.log('maxCollateralAmount', maxCollateralAmount);
        // console2.log('amountCollateral', amountCollateral);
        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // If price changes too fast, this test will cause revert
    // Solution : PRICE_CHANGE_PERCENT and PRICE_CHANGE_TIME_FRAME were added to detect
    // the fast price changing (change to often and price change out of setting limit)
    // DSCEngine__PriceChangeTooFrequent(), DSCEngine__PriceChangeExcessLimit() will be raised for such cases
    function updatePriceFeed(int256 price) public {
        if (block.timestamp < lastTimePriceChange + PRICE_CHANGE_TIME_FRAME) {
            return;
        }
        lastTimePriceChange = block.timestamp;

        int256 newPrice = bound(price, 1500e8, 2600e8);
        _updatePriceFeed(newPrice);
    }

    function _depositCollateral(address sender, ERC20Mock collateral, uint amountCollateral) private {
        collateral.mint(sender, amountCollateral);
        vm.startPrank(sender);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        haveDeposit.push(sender);
    }

    function _mint(address sender, uint amountMint) private {
        vm.startPrank(sender);
        dsce.mintDsc(amountMint);
        vm.stopPrank();
    }

    function _updatePriceFeed(int256 price) private {
        ethUsdPriceFeed.updateAnswer(price);
    }

    function _getCollateralAddress(uint collateralSeed) private view returns (ERC20Mock) {
        //return ERC20Mock(collateralTokens[0]);
        if (collateralSeed % 2 == 0) {
            return ERC20Mock(collateralTokens[0]);
        }
        return ERC20Mock(collateralTokens[1]);
    }
}
