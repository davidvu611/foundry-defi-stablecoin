// SPDX-License-Indicator:MIT
// Our invariantcs
// 1 - The total supply of DSC is less than the total value of collateral
// 2 - Getter view functions should never revert (evergreen)

pragma solidity ^0.8.18;

import { Test, console2 } from 'forge-std/Test.sol';
import { StdInvariant } from 'forge-std/StdInvariant.sol';
import { DeployDSC } from '../../script/DeployDSC.s.sol';
import { HelperConfig } from '../../script/HelperConfig.s.sol';
import { DSCEngine } from '../../src/DSCEngine.sol';
import { DecentralizedStableCoin } from '../../src/DecentralizedStableCoin.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { Handler } from './Handler.t.sol';

contract InvariantsTest is StdInvariant, Test {
    Handler handler;
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;
    address[] collateralTokens;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        config = helperConfig.getConfig();
        collateralTokens = dsce.getCollateralTokens();

        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public {
        uint totalSupply = dsc.totalSupply();
        uint totalWethDeposited = IERC20(config.wEth).balanceOf(address(dsce));
        uint totalWbtcDeposited = IERC20(config.wBtc).balanceOf(address(dsce));
        uint totalWethValue = dsce.getUsdValue(config.wEth, totalWethDeposited);
        uint totalWbtcValue = dsce.getUsdValue(config.wBtc, totalWbtcDeposited);

        // console2.log('----invariant-----');
        // console2.log('totalSupply', totalSupply);
        // console2.log('totalWethValue', totalWethValue);
        // console2.log('totalWbtcValue', totalWbtcValue);
        if (totalSupply > totalWethValue + totalWbtcValue) {
            console2.log('----invariant-----', totalSupply - (totalWethValue + totalWbtcValue));
            console2.log('Price ETH', dsce.getUsdValue(collateralTokens[0], 1 ether));
            console2.log('Price BTC', dsce.getUsdValue(collateralTokens[1], 1 ether));
            console2.log('Diff', totalSupply - (totalWethValue + totalWbtcValue));
        }
        assert(totalSupply <= totalWethValue + totalWbtcValue);
    }

    function invariant_getterFunctionNotRevert() public {
        dsce.getHealthFactor(msg.sender);
        dsce.getAccountCollateralValueInUsd(msg.sender);
        dsce.getAccountInformation(msg.sender);
        dsce.getCollateralBalanceOfUser(msg.sender, config.wEth);
        dsce.getCollateralBalanceOfUser(msg.sender, config.wBtc);
        dsce.getCollateralizedPercent();
        dsce.getCollateralTokens();
        dsce.getLiquidationBonusPercent();
        dsce.getTokenAmountFromUsd(config.wEth, 1e18);
        dsce.getTokenAmountFromUsd(config.wBtc, 1e18);
        dsce.getUsdValue(config.wEth, 1e18);
        dsce.getUsdValue(config.wBtc, 1e18);
        dsce.getPriceFeed(config.wEth);
        dsce.getPriceFeed(config.wBtc);
    }
}
