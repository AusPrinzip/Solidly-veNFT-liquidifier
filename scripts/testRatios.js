// scripts/testRatios.js
const { ethers } = require("hardhat");
const addr = require('./addresses.json');
const LiquidTokenArtifact = require('../artifacts/contracts/LiquidToken.sol/LiquidToken.json');
const ABI_LiquidToken = LiquidTokenArtifact.abi;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Testing as:", deployer.address);

  // Get the LiquidToken contract
  const liquidToken = new ethers.Contract(addr.LiquidToken, ABI_LiquidToken, deployer);
    
  // Get the current k value
  const k = await liquidToken.k();
  console.log(`Current k value: ${ethers.formatEther(k)} (${k.toString()} wei)`);
    
  // Test the deposit ratio for different lock periods
  const weekValues = [1, 26, 52, 78, 104];
    
  console.log("\nTesting deposit ratios for different lock periods:");
  console.log("--------------------------------------------------");
  console.log("Weeks | Deposit Ratio | Redeem Ratio");
  console.log("--------------------------------------------------");
    
  for (const weeks of weekValues) {
    const depositRatio = await liquidToken.calculateDepositRatio(weeks);
    const redeemRatio = await liquidToken.calculateRedeemRatio(weeks);
      
    console.log(
      `${weeks.toString().padEnd(5)} | ` +
      `${ethers.formatUnits(depositRatio, 18).padEnd(15)} | ` +
      `${ethers.formatUnits(redeemRatio, 18)}`
    );
  }
    
  // Test the actual amount of liTokens received for a fixed token amount with different lock periods
  const tokenAmount = ethers.parseEther("1000"); // 1000 tokens
    
  console.log("\nTokens received for 1000 underlying tokens with different lock periods:");
  console.log("------------------------------------------------------------------");
  console.log("Weeks | liTokens Received | Tokens Redeemable for 1000 liTokens");
  console.log("------------------------------------------------------------------");
    
  for (const weeks of weekValues) {
    const depositRatio = await liquidToken.calculateDepositRatio(weeks);
    const liTokensReceived = (tokenAmount * depositRatio) / ethers.parseEther("1");
      
    const redeemRatio = await liquidToken.calculateRedeemRatio(weeks);
    // Calculate how many underlying tokens would be received for 1000 liTokens
    const fixedLiTokens = ethers.parseEther("1000");
    // Corrected calculation: we divide by 10^18, not 10^36
    const tokensRedeemable = (fixedLiTokens * redeemRatio) / ethers.parseEther("1");
      
    console.log(
      `${weeks.toString().padEnd(5)} | ` +
      `${ethers.formatUnits(liTokensReceived, 18).padEnd(19)} | ` +
      `${ethers.formatUnits(tokensRedeemable, 18)}`
    );
  }
    
  // Test the loop fee (redeeming right after depositing)
  console.log("\nTesting deposit/redeem loop (loop fee):");
  console.log("-----------------------------------------------");
  console.log("Weeks | Deposit 1000 | Redeem Result | Loop Fee %");
  console.log("-----------------------------------------------");
    
  for (const weeks of weekValues) {
    const depositRatio = await liquidToken.calculateDepositRatio(weeks);
    const liTokensReceived = (tokenAmount * depositRatio) / ethers.parseEther("1");
      
    const redeemRatio = await liquidToken.calculateRedeemRatio(weeks);
    // Corrected calculation for tokensOnRedeem
    const tokensOnRedeem = (liTokensReceived * redeemRatio) / ethers.parseEther("1");
      
    // Calculate the loop fee percentage
    const loopFee = tokenAmount - tokensOnRedeem;
    const loopFeePercent = (loopFee * 10000n) / tokenAmount;
      
    console.log(
      `${weeks.toString().padEnd(5)} | ` +
      `${ethers.formatUnits(liTokensReceived, 18).padEnd(14)} | ` +
      `${ethers.formatUnits(tokensOnRedeem, 18).padEnd(15)} | ` +
      `${Number(loopFeePercent) / 100}%`
    );
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });