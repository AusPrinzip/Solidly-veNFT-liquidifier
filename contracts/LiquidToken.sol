// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import "./interfaces/IVotingEscrow.sol";
import "./strategies/Solidly.sol"; // Import the SolidlyStrategy interface

contract LiquidToken is ERC20, Ownable {
    
    address public immutable veNFT;
    address public immutable vault;
    address public immutable baseToken;
    
    uint256 public constant MAX_WEEKS = 104; // 2 years in weeks
    uint256 public constant WEEK = 7 * 86400; // One week in seconds
    
    // k is the current market price of liToken at week 0 (initially 1.0)
    uint256 public k = 10**18; // 1.0 in 18 decimals
    
    // Market variables
    uint256 public totalUnderlyingLocked; // Total amount of underlying tokens locked (AKA TVL)
    
    // Events
    event Deposit(address indexed user, uint256 tokenId, uint256 underlyingAmount, uint256 liTokenAmount, uint256 weeksRemaining);
    event Redeem(address indexed user, uint256 tokenId, uint256 underlyingAmount, uint256 liTokenAmount, uint256 weeksRemaining);
    event KUpdated(uint256 oldK, uint256 newK);

    constructor(
        string memory name, 
        string memory symbol, 
        address _veNFT, 
        address _vault,
        address _baseToken
    ) ERC20(name, symbol) Ownable(msg.sender) {
        veNFT = _veNFT;
        vault = _vault;
        baseToken = _baseToken;
    }
    
    /**
     * @dev Calculates the liToken/Token ratio based on weeks remaining
     * Formula: f(x) = k^(x/104 - 1)
     * @param weeksRemaining Number of weeks remaining in lock period (1-104)
     * @return The ratio in 18 decimals precision
     */
    function calculateDepositRatio(uint256 weeksRemaining) public view returns (uint256) {
        require(weeksRemaining > 0 && weeksRemaining <= 104, 'invalid lock');
        
        // Calculate x/104 as a fraction
        UD60x18 fraction = ud(10**18 * weeksRemaining / MAX_WEEKS);
        UD60x18 price = ud(k);

        return price.pow(fraction);
    }

    /**
     * @dev Calculates the Token/liToken ratio based on weeks remaining for redemption
     * This is the inverse of the deposit ratio
     * @param weeksRemaining Number of weeks remaining in lock period (1-104)
     * @return The redemption ratio in 18 decimals precision
     */
    function calculateRedeemRatio(uint256 weeksRemaining) public view returns (uint256) {
        // First, get the deposit ratio for the previous week (x-1) to create a "loop fee"
        uint256 adjustedWeeks = weeksRemaining <= 1 ? 1 : weeksRemaining - 1;
        
        // Get the deposit ratio
        uint256 depositRatio = calculateDepositRatio(adjustedWeeks);
        
        // The redemption ratio is the inverse of the deposit ratio from one week earlier
        // depositRatio(week-1) = liToken/Token, so redemption ratio = Token/liToken = 10^18 / depositRatio(week-1)
        // This creates a small "loop fee" to prevent deposit/redeem exploitation
        return (10**18) / depositRatio;
    }
    
    /**
     * @dev Updates the k value (market price factor)
     * This would typically be controlled by market dynamics or governance
     * @param newK The new k value (in 18 decimals)
     */
    function updateK(uint256 newK) external onlyOwner {
        require(newK >= 10**18, "K must be equal or greater than 1");
        emit KUpdated(k, newK);
        k = newK;
    }
    
    /**
     * @dev Deposits a veNFT and mints liquid tokens based on parabolic ratio
     * @param _tokenId The ID of the veNFT being deposited
     */
    function depositNFT(uint256 _tokenId) external {
        // Get the lock end time for the NFT
        uint256 lockEndTime = IVotingEscrow(veNFT).locked__end(_tokenId);
        require(lockEndTime > block.timestamp, "Invalid NFT: lock expired");
        
        // Get the token balance/amount
        uint256 underlyingAmount = IVotingEscrow(veNFT).balanceOfNFT(_tokenId);
        require(underlyingAmount > 0, "Invalid NFT: no locked amount");
        
        // Calculate weeks remaining in the lock (rounded up)
        uint256 weeksRemaining = (lockEndTime - block.timestamp + WEEK) / WEEK;
        weeksRemaining = weeksRemaining < 1 ? 1 : weeksRemaining;
        
        // Calculate liquid tokens to mint based on the ratio
        uint256 ratio = calculateDepositRatio(weeksRemaining);
        uint256 liTokenAmount = (underlyingAmount * ratio) / 10**18;
        
        // Transfer the NFT to the vault
        IVotingEscrow(veNFT).transferFrom(msg.sender, vault, _tokenId);
        
        // Call the strategy contract to handle age-bsaed merging
        SolidlyStrategy(vault).handleDeposit(_tokenId);

        // Update total underlying locked
        totalUnderlyingLocked += underlyingAmount;
        
        // Mint liquid tokens to the user
        _mint(msg.sender, liTokenAmount);
        
        emit Deposit(msg.sender, _tokenId, underlyingAmount, liTokenAmount, weeksRemaining);
    }
    
    /**
     * @dev Redeems liquid tokens for a specific amount of underlying tokens
     * @param _liTokenAmount The amount of liquid tokens to redeem
     * @param _tokenId The ID of the veNFT to redeem from
     */
    function redeem(uint256 _liTokenAmount, uint256 _tokenId) external {
        // Verify the NFT is in the vault
        require(IVotingEscrow(veNFT).ownerOf(_tokenId) == vault, "NFT not in vault");
        
        // Get the lock end time for the NFT
        uint256 lockEndTime = IVotingEscrow(veNFT).locked__end(_tokenId);
        
        // Prevent redemption for NFTs expiring within a week
        require(lockEndTime > block.timestamp + WEEK, "NFT expires too soon");
        
        // Get the token balance/amount of the NFT
        uint256 tokenBalance = IVotingEscrow(veNFT).balanceOfNFT(_tokenId);
        require(tokenBalance > 0, "Invalid NFT: no locked amount");
        
        // Calculate weeks remaining in the lock
        uint256 weeksRemaining = 0;
        if (lockEndTime > block.timestamp) {
            weeksRemaining = (lockEndTime - block.timestamp - WEEK) / WEEK;
            weeksRemaining = weeksRemaining < 1 ? 1 : weeksRemaining;
        }
        
        // Calculate the redemption ratio (Token/liToken ratio)
        uint256 ratio = calculateRedeemRatio(weeksRemaining);
        
        // Calculate how many underlying tokens can be redeemed with the provided liTokens
        // ratio is Token/liToken, so we multiply
        uint256 underlyingAmount = (_liTokenAmount * ratio) / 10**18;
        
        // Ensure the user is not trying to redeem more than the NFT holds
        require(underlyingAmount <= tokenBalance, "Redeem amount exceeds NFT balance");
        
        // Ensure the user has enough liquid tokens
        require(balanceOf(msg.sender) >= _liTokenAmount, "Insufficient liquid tokens");
        
        // If trying to redeem the entire NFT
        if (underlyingAmount == tokenBalance) {
            // Transfer the NFT back to the user
            IVotingEscrow(veNFT).transferFrom(vault, msg.sender, _tokenId);
        } else {
            // Split the NFT - need to call the vault/strategy to handle the split
            SolidlyStrategy(vault).splitAndSend(underlyingAmount, msg.sender);
        }
        
        // Only burn tokens after the split/transfer is successful
        _burn(msg.sender, _liTokenAmount);
        
        // Update total underlying locked
        totalUnderlyingLocked -= underlyingAmount;
        
        emit Redeem(msg.sender, _tokenId, underlyingAmount, _liTokenAmount, weeksRemaining);
    }
    
    /**
     * @dev View function to calculate how many liTokens a specific veNFT would receive
     * @param _tokenId The ID of the veNFT to query
     * @return liTokenAmount The amount of liquid tokens that would be received
     */
    function previewDeposit(uint256 _tokenId) external view returns (uint256 liTokenAmount) {
        // Get the lock end time for the NFT
        uint256 lockEndTime = IVotingEscrow(veNFT).locked__end(_tokenId);
        if (lockEndTime <= block.timestamp) return 0;
        
        // Get the token balance/amount
        uint256 underlyingAmount = IVotingEscrow(veNFT).balanceOfNFT(_tokenId);
        if (underlyingAmount <= 0) return 0;
        
        // Calculate weeks remaining in the lock
        uint256 weeksRemaining = (lockEndTime - block.timestamp + WEEK) / WEEK;
        weeksRemaining = weeksRemaining < 1 ? 1 : weeksRemaining;
        
        // Calculate liquid tokens to mint based on the ratio
        uint256 ratio = calculateDepositRatio(weeksRemaining);
        return (underlyingAmount * ratio) / 10**18;
    }
    
    /**
     * @dev View function to calculate how many underlying tokens would be received for redeeming liTokens
     * @param _liTokenAmount The amount of liquid tokens to redeem
     * @param _tokenId The ID of the veNFT to calculate redemption from
     * @return underlyingAmount The amount of underlying tokens that would be received
     * @return isFullRedeem Whether this would redeem the entire NFT
     */
    function previewRedeem(uint256 _liTokenAmount, uint256 _tokenId) external view returns (uint256 underlyingAmount, bool isFullRedeem) {
        // Verify the NFT is in the vault
        if (IVotingEscrow(veNFT).ownerOf(_tokenId) != vault) return (0, false);
        
        // Get the lock end time for the NFT
        uint256 lockEndTime = IVotingEscrow(veNFT).locked__end(_tokenId);
        
        // Get the token balance/amount of the NFT
        uint256 tokenBalance = IVotingEscrow(veNFT).balanceOfNFT(_tokenId);
        if (tokenBalance <= 0) return (0, false);
        
        // Calculate weeks remaining in the lock
        uint256 weeksRemaining = 0;
        if (lockEndTime > block.timestamp) {
            weeksRemaining = (lockEndTime - block.timestamp - WEEK) / WEEK;
            weeksRemaining = weeksRemaining < 1 ? 1 : weeksRemaining;
        }
        
        // Calculate the redemption ratio (Token/liToken ratio)
        uint256 ratio = calculateRedeemRatio(weeksRemaining);
        
        // Calculate underlying tokens based on the redemption ratio
        // ratio is Token/liToken, so we multiply
        underlyingAmount = (_liTokenAmount * ratio) / 10**18;
        
        // Check if this would be a full redemption of the NFT
        isFullRedeem = (underlyingAmount >= tokenBalance);
        
        // Cap the underlying amount to the available balance
        if (isFullRedeem) {
            underlyingAmount = tokenBalance;
        }
        
        return (underlyingAmount, isFullRedeem);
    }
}