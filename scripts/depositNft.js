// scripts/depositNft.js
const { ethers } = require("hardhat");
const addr = require('./addresses.json');
const ABI_WBNB = require('./abi/WBNB.json');
const ABI_veNFT = require('./abi/veNFT.json');
const LiquidTokenArtifact = require('../artifacts/contracts/LiquidToken.sol/LiquidToken.json');
const ABI_LiquidToken = LiquidTokenArtifact.abi;
const ONE_WEEK = 60 * 60 * 24 * 7;
const ONE = "1000000000000000000";

async function main() {
  const signers = await ethers.getSigners();
  const deployer = signers[0];
  const vault = signers[1];
  console.log("Transacting as:", deployer.address);

  // contracts
  const THE = new ethers.Contract(addr.THE, ABI_WBNB, deployer);
  const veTHE = new ethers.Contract(addr.veTHE, ABI_veNFT, deployer);
  const LiquidToken = new ethers.Contract(addr.LiquidToken, ABI_LiquidToken, deployer);

  try {
    let nftBalance = await veTHE.balanceOf(deployer.address);
    console.log('We own ' + nftBalance + ' veNFTs');

    // DEPOSIT NFT
    console.log('checking approval');
    let isApprovedForAll = await veTHE.isApprovedForAll(deployer.address, addr.LiquidToken);
    console.log(isApprovedForAll + ' approval');
    if (!isApprovedForAll) {
      console.log('approving veTHE');
      await veTHE.setApprovalForAll(addr.LiquidToken, true);
    }

    // Get the tokenId of the first NFT
    const tokenId = await veTHE.tokenOfOwnerByIndex(deployer.address, 0);
    console.log('Using tokenId:', tokenId.toString());

    // Step 1: Check lock
    const lockEndTime = await veTHE.locked__end(tokenId);
    console.log('Lock end time OK:', lockEndTime > Math.floor(Date.now() / 1000));

    // Step 1b: check expiry
    const expiresInWeeks = (lockEndTime - Date.now()) / ONE_WEEK;
    console.log(`veNFT expires in ${expiresInWeeks}`)

    // Step 2: Check underlying amount
    const amount = await veTHE.balanceOfNFT(tokenId);
    console.log('Underlying amount:', amount.toString());
    console.log('Underlying amount OK:', amount.toString() !== '0');

    // Step 3: Try to get veNFT interface data - this might reveal any issues
    console.log('NFT owner:', await veTHE.ownerOf(tokenId));

    // Get the initial liToken balance
    const initialLiBalance = await LiquidToken.balanceOf(deployer.address);
    console.log('Initial liToken balance:', ethers.formatUnits(initialLiBalance));

    // Preview the deposit to see how many liTokens we should receive
    const previewAmount = await LiquidToken.previewDeposit(tokenId);
    console.log('Preview liToken amount:', ethers.formatUnits(previewAmount));

    // Deposit the NFT
    console.log('Depositing NFT...');
    const tx = await LiquidToken.depositNFT(tokenId);
    await tx.wait();
    console.log('Deposit complete');

    // Get the new liToken balance
    const newLiBalance = await LiquidToken.balanceOf(deployer.address);
    console.log('New liToken balance:', ethers.formatUnits(newLiBalance));

    // Calculate the actual received amount
    const actualReceived = newLiBalance - initialLiBalance;
    console.log('Actual received liTokens:', ethers.formatUnits(actualReceived));

    // Calculate ratio
    const ratio = await LiquidToken.calculateDepositRatio(expiresInWeeks)
    console.log(`Exchange ratio: ${ratio} liToken/Token`)
    // Compare preview with actual received amount
    const difference = actualReceived - previewAmount;
    const percentDifferenceBigInt = (difference * 10000n) / previewAmount;
    const percentDifference = Number(percentDifferenceBigInt) / 100;
      
    console.log('\n--- Verification Results ---');
    console.log('Preview amount:      ', ethers.formatUnits(previewAmount));
    console.log('Actual received:     ', ethers.formatUnits(actualReceived));
    console.log('Difference:          ', ethers.formatUnits(difference));
    console.log('Difference (%):      ', percentDifference.toFixed(6) + '%');
      
    if (difference == 0n) {
      console.log('✅ VERIFICATION PASSED: Preview matches actual received amount');
    } else {
      console.log('❌ VERIFICATION FAILED: Preview does not match actual received amount');
    }

  } catch (error) {
    console.error("Error during transacting:", error);
    process.exit(1);
  }
}

// Execute the deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });