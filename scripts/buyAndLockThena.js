// scripts/buyAndLockThena.js
const { ethers } = require("hardhat");
const addr = require('./addresses.json');
const ABI_WBNB = require('./abi/WBNB.json');
const ABI_RouterV2 = require('./abi/RouterV2.json');
const ABI_veNFT = require('./abi/veNFT.json');
// Using Node.js built-in readline module (no external dependencies)
const readline = require('readline');

// Create readline interface for CLI prompts
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// Helper function to prompt user for input
function prompt(question) {
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      resolve(answer);
    });
  });
}

async function main() {
  try {
    const [deployer] = await ethers.getSigners();
    console.log("Transacting as:", deployer.address);
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("Account balance:", ethers.formatEther(balance), "BNB");

    // Get contracts
    const THE = new ethers.Contract(addr.THE, ABI_WBNB, deployer);
    const WBNB = new ethers.Contract(addr.WBNB, ABI_WBNB, deployer);
    const RouterV2 = new ethers.Contract(addr.RouterV2, ABI_RouterV2, deployer);
    const veTHE = new ethers.Contract(addr.veTHE, ABI_veNFT, deployer);

    // Prompt user for amount and lock time
    const amountBNB = await prompt("Enter amount of BNB to swap for THE: ");
    const lockWeeks = await prompt("Enter lock duration in weeks (1-104): ");

    // Close readline interface
    rl.close();

    // Convert to BigInt with correct units
    const amountBNBWei = ethers.parseEther(amountBNB);
    const lockTimeSeconds = parseInt(lockWeeks) * 7 * 86400; // Convert weeks to seconds

    // Validate input
    if (parseInt(lockWeeks) < 1 || parseInt(lockWeeks) > 104) {
      console.error("Lock time must be between 1 and 104 weeks");
      process.exit(1);
    }

    console.log(`\nExecuting transaction to buy ${amountBNB} BNB worth of THE and lock for ${lockWeeks} weeks...`);

    // Step 1: Check WBNB balance and wrap if needed
    let balWBNB = await WBNB.balanceOf(deployer.address);
    console.log(`Current WBNB balance: ${ethers.formatEther(balWBNB)} WBNB`);

    if (balWBNB < amountBNBWei) {
      console.log(`Wrapping ${amountBNB} BNB to WBNB...`);
      const wrapTx = await WBNB.deposit({ value: amountBNBWei });
      await wrapTx.wait();
      console.log("BNB wrapped successfully");
      balWBNB = await WBNB.balanceOf(deployer.address);
      console.log(`New WBNB balance: ${ethers.formatEther(balWBNB)} WBNB`);
    }

    // Step 2: Check WBNB approval in RouterV2
    let allowance = await WBNB.allowance(deployer.address, addr.RouterV2);
    if (allowance < amountBNBWei) {
      console.log('Approving RouterV2 for WBNB...');
      const approveTx = await WBNB.approve(addr.RouterV2, amountBNBWei);
      await approveTx.wait();
      console.log("Router approval successful");
    }

    // Step 3: Get quote WBNB -> THE
    let result = await RouterV2.getAmountOut(amountBNBWei, addr.WBNB, addr.THE);
    const expectedTHE = ethers.formatEther(result[0]);
    console.log(`Expected swap result: ${amountBNB} WBNB -> ${expectedTHE} THE`);

    // Step 4: Execute swap
    let routes = [
      {
        from: addr.WBNB,
        to: addr.THE,
        stable: false
      }
    ];
    
    let deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes
    console.log("Executing swap...");
    const swapTx = await RouterV2.swapExactTokensForTokens(
      amountBNBWei, 
      0, // Min output (set to 0 for simplicity, but in production should include slippage protection)
      routes, 
      deployer.address, 
      deadline
    );
    await swapTx.wait();

    // Step 5: Check THE balance after swap
    let theBal = await THE.balanceOf(deployer.address);
    console.log(`Swap completed. THE balance: ${ethers.formatEther(theBal)} THE`);

    // Step 6: Approve veTHE to spend THE
    let theAllowance = await THE.allowance(deployer.address, addr.veTHE);
    if (theAllowance < theBal) {
      console.log('Approving veTHE for THE...');
      const approveTHETx = await THE.approve(addr.veTHE, theBal);
      await approveTHETx.wait();
      console.log("veTHE approval successful");
    }

    // Step 7: Create lock for THE
    console.log(`Creating lock for ${ethers.formatEther(theBal)} THE for ${lockWeeks} weeks...`);
    const lockTx = await veTHE.create_lock(theBal, lockTimeSeconds);
    await lockTx.wait();
    
    // Step 8: Verify NFT balance
    const nftBalance = await veTHE.balanceOf(deployer.address);
    console.log(`\nTransaction successful!`);
    console.log(`You now own ${nftBalance.toString()} veNFTs`);
    
    // Print details of the newest NFT
    if (nftBalance > 0n) {
      // Convert to number for array index
      const nftBalanceNum = Number(nftBalance);
      const tokenId = await veTHE.tokenOfOwnerByIndex(deployer.address, nftBalanceNum - 1);
      const lockInfo = await veTHE.locked(tokenId);
      const lockEnd = await veTHE.locked__end(tokenId);
      const lockAmount = lockInfo[0];
      
      console.log(`\nNFT Details:`);
      console.log(`Token ID: ${tokenId.toString()}`);
      console.log(`Locked Amount: ${ethers.formatEther(lockAmount)} THE`);
      console.log(`Lock End: ${new Date(Number(lockEnd) * 1000).toLocaleString()}`);
    }

  } catch (error) {
    console.error("Error during transaction:", error);
    // Make sure to close readline if we hit an error
    if (rl.active) rl.close();
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