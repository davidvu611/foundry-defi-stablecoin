// SPDX-License-Identicator:MIT
pragma solidity ^0.8.18;

import { Script, console2 } from 'forge-std/Script.sol';
import { DecentralizedStableCoin } from '../src/DecentralizedStableCoin.sol';
import { DSCEngine } from '../src/DSCEngine.sol';
import { HelperConfig } from './HelperConfig.s.sol';

contract DeployDSC is Script {
    address[] private tokenAddresses;
    address[] private priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();
        tokenAddresses = [networkConfig.wEth, networkConfig.wBtc];
        priceFeedAddresses = [networkConfig.wEthPriceFeed, networkConfig.wBtcPriceFeed];

        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();

        // console2.log('chainid', block.chainid);
        // console2.log('wEth', networkConfig.wEth);
        // console2.log('wBtc', networkConfig.wBtc);
        // console2.log('wEthPriceFeed', networkConfig.wEthPriceFeed);
        // console2.log('wBtcPriceFeed', networkConfig.wBtcPriceFeed);
        // console2.log('deployerKey', networkConfig.deployerKey);
        // console2.log('tokenAddresses', tokenAddresses[0], tokenAddresses[1]);
        // console2.log('priceFeedAddresses', priceFeedAddresses[0], priceFeedAddresses[1]);
        // console2.log('dsc', address(dsc));
        return (dsc, engine, helperConfig);
    }
}
