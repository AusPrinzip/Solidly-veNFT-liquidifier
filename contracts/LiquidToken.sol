// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IVotingEscrow.sol";

struct LockedBalance {
    int128 amount;
    uint end;
}

contract LiquidToken is ERC20 {
    address veNFT;
    address vault;

    constructor(string memory name, string memory symbol, address _veNFT, address _vault)
        ERC20(name, symbol)
    {
        veNFT = _veNFT;
        vault = _vault;
    }

    // people will need to veNFT.approve(this contract)
    // before calling this function the first time
    function depositNFT( // veNFT to likTOK
        uint256 _tokenId
    ) external {
        IVotingEscrow(veNFT).transferFrom(msg.sender, vault, _tokenId);
        _mint(msg.sender, 10**18);
    }

    // the vault needs to approveAll the LiquidToken
    function redeem(uint256 _tokenId) external {
        _burn(msg.sender, 10**18);
        IVotingEscrow(veNFT).transferFrom(vault, msg.sender, _tokenId);
    }

    // function depositAndRedeem() {}
}