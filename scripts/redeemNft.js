// scripts/redeemNft.js
const { ethers } = require("hardhat");
const addr = require('./addresses.json');
const ABI_WBNB = require('./abi/WBNB.json');
const ABI_veNFT = require('./abi/veNFT.json');
const LiquidTokenArtifact = require('../artifacts/contracts/LiquidToken.sol/LiquidToken.json');
const ABI_LiquidToken = LiquidTokenArtifact.abi;
const ONE_WEEK = 60 * 60 * 24 * 7;

async function main() {
  const signers = await ethers.getSigners();
  const deployer = signers[0];
  const vault = addr.Strategy;
  console.log("Transacting as:", deployer.address);

  // Contracts
  const THE = new ethers.Contract(addr.THE, ABI_WBNB, deployer);
  const veTHE = new ethers.Contract(addr.veTHE, ABI_veNFT, deployer);
  const LiquidToken = new ethers.Contract(addr.LiquidToken, ABI_LiquidToken, deployer);

  try {
    // Check user NFT balance
    let userNftBalance = await veTHE.balanceOf(deployer.address);
    console.log('We own ' + userNftBalance + ' veNFTs');

    // Check liTHE balance
    let liBal = await LiquidToken.balanceOf(deployer.address);
    console.log(`Liquid token balance: ${ethers.formatUnits(liBal)} liTOK`);

    // Ensure we have enough liTokens to redeem
    if (liBal < ethers.parseEther("0.1")) {
      console.error("Not enough liTokens to redeem. Need at least 0.1");
      process.exit(1);
    }

    // Check if vault has any NFTs
    const vaultNftBalance = await veTHE.balanceOf(vault);
    console.log(`Vault NFT balance: ${vaultNftBalance}`);
    
    if (vaultNftBalance === 0n) {
      console.error("Vault doesn't own any NFTs to redeem against");
      process.exit(1);
    }

    // Retrieve the first tokenId from vault
    const tokenId = await veTHE.tokenOfOwnerByIndex(vault, 0);
    console.log(`Target NFT for redemption: ${tokenId}`);

    // Get NFT details
    const lockInfo = await veTHE.locked(tokenId);
    const lockEnd = await veTHE.locked__end(tokenId);
    const currentBlock = await ethers.provider.getBlock("latest");
    const currentTime = currentBlock.timestamp;
    
    // Check if NFT is still locked
    if (lockEnd <= currentTime) {
      console.error("NFT lock has expired. Cannot redeem against it.");
      process.exit(1);
    }

    const tokenBalance = lockInfo[0];
    console.log(`NFT underlying balance: ${ethers.formatUnits(tokenBalance)} THE`);
    console.log(`NFT lock end: ${new Date(Number(lockEnd) * 1000).toLocaleString()}`);

    // Get NFT voting power
    const votingPower = await veTHE.balanceOfNFT(tokenId);
    console.log(`NFT voting power: ${ethers.formatUnits(votingPower)} veNFT units`);

    // Calculate weeks remaining
    let weeksRemaining = Math.floor((Number(lockEnd) - currentTime) / ONE_WEEK);
    weeksRemaining = weeksRemaining < 1 ? 1 : weeksRemaining;
    console.log(`Weeks remaining in lock: ${weeksRemaining}`);

    // Try different percentages of the NFT for redemption
    console.log("\nTesting different redemption percentages:");
    console.log("------------------------------------");
    
    // Calculate how much of the NFT can be redeemed with different percentages
    const totalNftValue = Number(ethers.formatUnits(tokenBalance));
    const percentages = [5, 10, 20, 30, 40, 50];
    
    const validOptions = [];
    
    for (const percentage of percentages) {
      // Calculate a percentage of the NFT's underlying token amount
      const targetAmount = ethers.parseUnits((totalNftValue * percentage / 100).toFixed(18), 18);
      
      // Calculate required liTOK to redeem this amount
      const ratio = await LiquidToken.calculateRedeemRatio(weeksRemaining);
      const requiredLiTokens = (targetAmount * ethers.parseEther("1")) / ratio;
      
      // Skip if user doesn't have enough
      if (requiredLiTokens > liBal) continue;
      
      try {
        // Check if this redemption would be valid
        const [redeemable, fullRedeem] = await LiquidToken.previewRedeem(requiredLiTokens, tokenId);
        
        // Verify the redemption amount is sensible
        if (redeemable > 0n && redeemable < tokenBalance) {
          console.log(`${percentage}% of NFT: ${ethers.formatEther(requiredLiTokens)} liTOK → ${ethers.formatEther(redeemable)} THE`);
          validOptions.push({
            percentage,
            liTokens: requiredLiTokens,
            redeemable
          });
        }
      } catch (error) {
        // Skip options that cause errors
        continue;
      }
    }
    
    if (validOptions.length === 0) {
      console.error("\nCould not find a valid redemption amount based on percentage splits. Try custom amounts.");
      
      // Try standard amounts instead
      const testAmounts = [
        ethers.parseEther("0.1"),
        ethers.parseEther("0.5"),
        ethers.parseEther("1.0"),
        ethers.parseEther("5.0"),
        liBal > ethers.parseEther("50.0") ? ethers.parseEther("50.0") : liBal
      ];
  
      console.log("\nTesting standard redemption amounts:");
      console.log("------------------------------------");
      
      for (const amount of testAmounts) {
        if (amount > liBal) continue;
        
        try {
          const [redeemable, fullRedeem] = await LiquidToken.previewRedeem(amount, tokenId);
          console.log(`${ethers.formatEther(amount)} liTOK → ${ethers.formatEther(redeemable)} THE (Full redeem: ${fullRedeem})`);
          
          // Check if redeemable amount is valid
          if (redeemable > 0n && redeemable < tokenBalance) {
            validOptions.push({
              percentage: null,
              liTokens: amount,
              redeemable
            });
          }
        } catch (error) {
          console.log(`Error previewing ${ethers.formatEther(amount)} liTOK: ${error.message}`);
        }
      }
    }
    
    if (validOptions.length === 0) {
      console.error("\nCould not find any valid redemption amounts. The veNFT might have restrictions on split amounts.");
      process.exit(1);
    }

    // Prompt user for manual amount entry
    const readline = require('readline');
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    console.log("\nValid redemption options:");
    validOptions.forEach((option, index) => {
      if (option.percentage) {
        console.log(`${index + 1}. ${option.percentage}% of NFT: ${ethers.formatEther(option.liTokens)} liTOK → ${ethers.formatEther(option.redeemable)} THE`);
      } else {
        console.log(`${index + 1}. Standard: ${ethers.formatEther(option.liTokens)} liTOK → ${ethers.formatEther(option.redeemable)} THE`);
      }
    });
    
    let finalAmount;
    const selectionPrompt = await new Promise((resolve) => {
      rl.question('\nSelect an option (1-' + validOptions.length + ') or enter "c" to input a custom amount: ', resolve);
    });
    
    if (selectionPrompt.toLowerCase() === 'c') {
      const customAmount = await new Promise((resolve) => {
        rl.question('\nEnter custom amount of liTOK to redeem: ', resolve);
      });
      
      try {
        finalAmount = ethers.parseEther(customAmount);
        
        // Validate custom amount
        if (finalAmount <= 0n) {
          console.error('Invalid amount. Must be greater than 0.');
          rl.close();
          process.exit(1);
        }
        
        if (finalAmount > liBal) {
          console.error(`Amount exceeds your balance of ${ethers.formatEther(liBal)} liTOK`);
          rl.close();
          process.exit(1);
        }
        
        // Preview the redemption with custom amount
        const [redeemable, fullRedeem] = await LiquidToken.previewRedeem(finalAmount, tokenId);
        
        // Check if the amount would cause an error
        if (redeemable === 0n || redeemable >= tokenBalance) {
          console.error('This amount would likely cause a "Invalid split amount" error. Try a different amount.');
          rl.close();
          process.exit(1);
        }
        
        console.log(`\nYou will receive approximately ${ethers.formatEther(redeemable)} THE`);
      } catch (error) {
        console.error(`Invalid input: ${error.message}`);
        rl.close();
        process.exit(1);
      }
    } else {
      // Use selected option
      const selection = parseInt(selectionPrompt) - 1;
      if (isNaN(selection) || selection < 0 || selection >= validOptions.length) {
        console.error('Invalid selection');
        rl.close();
        process.exit(1);
      }
      
      finalAmount = validOptions[selection].liTokens;
      console.log(`\nYou selected: ${ethers.formatEther(finalAmount)} liTOK → ${ethers.formatEther(validOptions[selection].redeemable)} THE`);
    }
    
    // Final confirmation
    const confirmAnswer = await new Promise((resolve) => {
      rl.question('\nConfirm redemption? (yes/no): ', resolve);
    });
    rl.close();

    if (confirmAnswer.toLowerCase() !== 'yes') {
      console.log('Redemption cancelled by user');
      process.exit(0);
    }

    // Execute the redemption
    console.log('\nExecuting redemption...');
    const tx = await LiquidToken.redeem(finalAmount, tokenId);
    console.log(`Transaction hash: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`Transaction confirmed in block ${receipt.blockNumber}`);

    // Check NFT balance after redemption
    const newNftBalance = await veTHE.balanceOf(deployer.address);
    console.log(`\nNew NFT balance: ${newNftBalance}`);
    
    if (newNftBalance > 0) {
      console.log('\nAll NFTs for this account:');
      for (let i = 0; i < newNftBalance; i++) {
        const nft = await veTHE.tokenOfOwnerByIndex(deployer.address, i);
        const nftInfo = await veTHE.locked(nft);
        const nftBal = nftInfo[0];
        const nftUnlock = nftInfo[1];
        console.log(`NFT #${i}: ID ${nft}, Balance: ${ethers.formatEther(nftBal)} THE, Unlock: ${new Date(Number(nftUnlock) * 1000).toLocaleString()}`);
      }
    }

    // Check liToken balance after redemption
    const newLiBal = await LiquidToken.balanceOf(deployer.address);
    console.log(`\nNew liquid token balance: ${ethers.formatUnits(newLiBal)} liTOK`);
    console.log(`Redeemed: ${ethers.formatUnits(liBal - newLiBal)} liTOK`);

  } catch (error) {
    console.error("Error during transacting:", error);
    process.exit(1);
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });