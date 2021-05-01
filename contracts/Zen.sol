// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./libraries/Address.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IPancakeFactory.sol";
import "./BEP20.sol";

// ZenToken with Governance.
contract Zen is BEP20('Zen', 'ZEN') {
    address public pancakeZenBNBPair;
    address public pancakeZenUSDPair;

    constructor (
        IPancakeFactory pancakeFactory,
        address bnb,
        address usd
    ) public {
        pancakeZenBNBPair = pancakeFactory.createPair(address(this), bnb);
        pancakeZenUSDPair = pancakeFactory.createPair(address(this), usd);
    }

    function burnFrom(address account, uint256 amount) public onlyOwner() {
        _burn(account, amount);
    }

    function getPairs() public view returns (address, address) {
        return (pancakeZenBNBPair, pancakeZenUSDPair);
    }

    function circulatingSupply() public view returns (uint256) {
        (address zenBNB, address zenBUSD) = this.getPairs();
        return this.totalSupply().sub(this.balanceOf(zenBNB)).sub(this.balanceOf(zenBUSD));
    }
}