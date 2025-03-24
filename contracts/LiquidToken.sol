// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LiquidToken is ERC20 {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
    { }

    function depositNFT( // veNFT to likTOK
        uint256 _tokenId
    ) external {
        // people will need to veNFT.approve(this contract)
        // veNFT.transferFrom(tokenId, msg.sender, vault)
        // _mint(account, amount);
    }

    function redeem(uint256 amount, uint256 nweeks) external {
        // _burn(account, amount);
        // send them nft
    }
}