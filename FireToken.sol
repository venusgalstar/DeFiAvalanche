//Contract based on https://docs.openzeppelin.com/contracts/3.x/erc721
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
contract FireToken is ERC20, Ownable {
    constructor(address owner, uint256 tokenCount) ERC20("FIRE", "FIRE") {
        super._mint(owner, tokenCount * 10**18);
    }
}