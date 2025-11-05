// // SPDX-License-Indicator:MIT
// // Our invariantcs
// // 1 - The total supply of DSC is less than the total value of collateral
// // 2 - Getter view functions should never revert (evergreen)

// pragma solidity ^0.8.18;

// import { Test } from 'forge-std/Test.sol';
// import { StdInvariant } from 'forge-std/StdInvariant.sol';
// import { DeployDSC } from '../../script/DeployDSC.s.sol';
// import { HelperConfig } from '../../script/HelperConfig.s.sol';
// import { DSCEngine } from '../../src/DSCEngine.sol';
// import { DecentralizedStableCoin } from '../../src/DecentralizedStableCoin.sol';
// import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDSC deployer;
//     DSCEngine dsce;
//     DecentralizedStableCoin dsc;
//     HelperConfig helperConfig;
//     HelperConfig.NetworkConfig config;

//     function setUp() public {
//         deployer = new DeployDSC();
//         (dsc, dsce, helperConfig) = deployer.run();
//         config = helperConfig.getConfig();
//         targetContract(address(dsce));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         uint totalSupply = dsc.totalSupply();
//         uint totalWethDeposited = IERC20(config.wEth).balanceOf(address(dsc));
//         uint totalWbtcDeposited = IERC20(config.wBtc).balanceOf(address(dsc));
//         uint totalWethValue = dsce.getUsdValue(config.wEth, totalWethDeposited);
//         uint totalWbtcValue = dsce.getUsdValue(config.wBtc, totalWbtcDeposited);
//         assert(totalSupply <= totalWethValue + totalWbtcValue);
//     }
// }
