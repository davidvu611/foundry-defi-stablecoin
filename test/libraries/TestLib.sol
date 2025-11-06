// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import { DSCEngine } from '../../src/DSCEngine.sol';

library TestLib {
    function getPriceInUsd(DSCEngine dscEngine, address collateralToken) public view returns (uint256) {
        return dscEngine.getUsdValue(collateralToken, 1) * 1e8;
    }

    function getMaxCollateralToCover(
        DSCEngine dscEngine,
        uint256 mintAmount,
        address collateral
    ) public view returns (uint256) {
        uint256 priceInUsd = getPriceInUsd(dscEngine, collateral);
        uint256 collateralizedPercent = dscEngine.getCollateralizedPercent();
        return (mintAmount * collateralizedPercent) / 100 / (priceInUsd / 1e8);
    }

    function getMaxMintFromCollateral(
        DSCEngine dscEngine,
        address collateralToken,
        uint256 collateralAmount
    ) public view returns (uint256) {
        uint256 priceInUsd = getPriceInUsd(dscEngine, collateralToken) / 1e8;
        uint256 collateralInUsd = (collateralAmount * priceInUsd);
        return getMaxMintFromUsd(dscEngine, collateralInUsd);
        //maxMintAmount = (collateralInUsd * 100) / dscEngine.getCollateralizedPercent();
        // console2.log('------getMaxMintAmount-------');
        // console2.log('collateralAmount', collateralAmount);
        // console2.log('priceInUsd', priceInUsd);
        // console2.log('collateralInUsd', collateralInUsd);
        // console2.log('maxMintAmount', maxMintAmount);
    }

    function getMaxMintFromUsd(
        DSCEngine dscEngine,
        uint256 collateralInUsd
    ) public pure returns (uint256 maxMintAmount) {
        maxMintAmount = (collateralInUsd * 100) / dscEngine.getCollateralizedPercent();
    }
}
