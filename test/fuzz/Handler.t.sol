// SPDX-License-Indicator:MIT
pragma solidity ^0.8.18;

import { Test } from 'forge-std/Test.sol';
import { DSCEngine } from '../../src/DSCEngine.sol';
import { DecentralizedStableCoin } from '../../src/DecentralizedStableCoin.sol';

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;
    }

    function depositCollateral(address collateral, uint amount) public {
        dsce.depositCollateral(collateral, amount);
    }
}
