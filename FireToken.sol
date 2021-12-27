// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FireToken is ERC20, Ownable {
    constructor(address owner, uint256 tokenCount) ERC20("FIRE", "FIRE") {
        super._mint(owner, tokenCount * 10**18);
    }
}