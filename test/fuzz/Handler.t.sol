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
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    address[] collateralTokens;
    MockV3Aggregator ethUsdPriceFeed;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;
        collateralTokens = dsce.getCollateralTokens();
        ethUsdPriceFeed = MockV3Aggregator(dsce.getPriceFeed(collateralTokens[0]));
        //ethUsdPriceFeed.updateAnswer(7176);
    }

    function mint(uint amount) public {
        (uint totalMint, uint collateralInUsd) = dsce.getAccountInformation(msg.sender);
        uint256 maxMintAmount = TestLib.getMaxMintFromUsd(dsce, collateralInUsd) - totalMint;

        if (maxMintAmount <= 0) {
            return;
        }
        amount = bound(amount, 0, maxMintAmount);
        if (amount <= 0) {
            return;
        }
        // console2.log('--------Mint---------');
        // console2.log('collateralInUsd', collateralInUsd);
        // console2.log('maxMintAmount', maxMintAmount);
        // console2.log('totalMint', totalMint);
        // console2.log('collateralInUsd', collateralInUsd);
        //console2.log('amount', amount);

        vm.startPrank(msg.sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
    }

    function depositCollateral(uint collateralSeed, uint amount) public {
        ERC20Mock collateral = _getCollateralAddress(collateralSeed);
        uint amountCollateral = bound(amount, 1, MAX_DEPOSIT_AMOUNT);
        collateral.mint(msg.sender, amountCollateral);

        vm.startPrank(msg.sender);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // console2.log('--------Deposit---------');
        // console2.log('Deposit ', amountCollateral);
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

    // Cause revert??
    // function updatePriceFeed(uint96 _price) public {
    //     int256 price = int256(uint256(_price));
    //     if (price < 1e8) {
    //         return;
    //     }
    //     console2.log('update price', price);
    //     ethUsdPriceFeed.updateAnswer(price);
    // }

    function _getCollateralAddress(uint collateralSeed) private view returns (ERC20Mock) {
        //return ERC20Mock(collateralTokens[0]);
        if (collateralSeed % 2 == 0) {
            return ERC20Mock(collateralTokens[0]);
        }
        return ERC20Mock(collateralTokens[1]);
    }
}
