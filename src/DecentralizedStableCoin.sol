// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { ERC20Burnable, ERC20 } from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountMustMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExcessBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20('Decentralized Stable Coins', 'DSC') {}

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustMoreThanZero();
        }
        uint balance = balanceOf(msg.sender);
        if (_amount > balance) {
            revert DecentralizedStableCoin__BurnAmountExcessBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
