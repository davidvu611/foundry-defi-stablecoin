// SPDX-License-Identicator:MIT
pragma solidity ^0.8.18;

import { Script } from 'forge-std/Script.sol';
import { MockV3Aggregator } from '../test/mocks/MockV3Aggregator.sol';
import { ERC20Mock } from '@openzeppelin/contracts/mocks/ERC20Mock.sol';

abstract contract CodeConstants {
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    uint8 public constant PRICE_FEED_DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 50000e8;
    uint256 public DEFAULT_ENVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();
    NetworkConfig activeNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;
    struct NetworkConfig {
        address wEthPriceFeed;
        address wBtcPriceFeed;
        address wEth;
        address wBtc;
        uint256 deployerKey;
    }

    constructor() {
        networkConfigs[LOCAL_CHAIN_ID] = getOrCreateAnvilEthConfig();
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[ETH_MAINNET_CHAIN_ID] = getMainnetEthConfig();
        activeNetworkConfig = networkConfigs[block.chainid];
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
        //return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public view returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAIN_ID && chainId != ETH_SEPOLIA_CHAIN_ID && chainId != ETH_MAINNET_CHAIN_ID) {
            revert HelperConfig__InvalidChainId();
        }
        return networkConfigs[chainId];
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                wEthPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                wBtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                wEth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
                wBtc: 0x29f2D40B0605204364af54EC677bD022dA425d03,
                deployerKey: vm.envUint('PRIVATE_KEY')
            });
    }

    function getMainnetEthConfig() public view returns (NetworkConfig memory) {
        // Test
        return getSepoliaEthConfig();
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wEthPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        ERC20Mock wethMock = new ERC20Mock('ETH wrapped token', 'WETC', msg.sender, 1000e8);
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, ETH_USD_PRICE);

        ERC20Mock wbtcMock = new ERC20Mock('BTC wrapped token', 'WBTC', msg.sender, 1000e8);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, BTC_USD_PRICE);
        vm.stopBroadcast();
        return
            NetworkConfig({
                wEthPriceFeed: address(ethUsdPriceFeed),
                wBtcPriceFeed: address(btcUsdPriceFeed),
                wEth: address(wethMock),
                wBtc: address(wbtcMock),
                deployerKey: DEFAULT_ENVIL_KEY
            });
    }
}
