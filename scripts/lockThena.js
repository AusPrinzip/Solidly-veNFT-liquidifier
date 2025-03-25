// scripts/deploy.js
const { ethers } = require("hardhat");
const addr = require('./addresses.json')
const ABI_WBNB = require('./abi/WBNB.json')
const ABI_veNFT = require('./abi/veNFT.json')
const ABI_LiquidToken = require('./abi/LiquidToken.json')
const ONE_WEEK = 60 * 60 * 24 * 7
const ONE = "1000000000000000000"

async function main() {
  const signers = await ethers.getSigners();
  const deployer = signers[0]
  const vault = signers[1]
  console.log("Transacting as:", deployer.address)

  // contracts
  const THE = new ethers.Contract(addr.THE, ABI_WBNB, deployer)
  const veTHE = new ethers.Contract(addr.veTHE, ABI_veNFT, deployer)
  const LiquidToken = new ethers.Contract(addr.LiquidToken, ABI_LiquidToken, deployer)

  try {
    // CREATE LOCK

    // let balTHE = await THE.balanceOf(deployer.address)
    // console.log('THE: '+ethers.formatEther(balTHE))
    // let allowance = await THE.allowance(deployer.address, addr.veTHE)
    // if (allowance < BigInt(ONE)) {
    //   console.log('Approving veTHE for 1 THE')
    //   await THE.approve(addr.veTHE, ONE)
    // }
    // await veTHE.create_lock(ONE, ONE_WEEK)

    let nftBalance = await veTHE.balanceOf(deployer.address)
    console.log('We own '+nftBalance+' veNFTs')

    // for (let i = 0; i < nftBalance; i++) {
    //   let nft = await veTHE.tokenOfOwnerByIndex(deployer.address, i)
    //   let nftInfo = await veTHE.locked(nft)
    //   let nftBal = nftInfo[0]
    //   let nftUnlock = nftInfo[1]
    //   console.log(nft, nftBal, nftUnlock)
    // }

    // DEPOSIT NFT
    // console.log('checking approval')
    // let isApprovedForAll = await veTHE.isApprovedForAll(deployer.address, addr.LiquidToken)
    // console.log(isApprovedForAll+' approval')
    // if (!isApprovedForAll) {
    //   console.log('approving veTHE')
    //   await veTHE.setApprovalForAll(addr.LiquidToken, true);
    // }
    // let tokenId = await veTHE.tokenOfOwnerByIndex(deployer.address, 0)
    // console.log('Depositing token '+tokenId)
    // await LiquidToken.depositNFT(tokenId)

    // check liTHE balance
    let liBal = await LiquidToken.balanceOf(deployer.address)
    console.log(ethers.formatUnits(liBal)+' liTOK')

    // REDEEM NFT
    // console.log('checking approval')
    // let isApprovedForAll = await veTHE.isApprovedForAll(vault.address, addr.LiquidToken)
    // console.log(isApprovedForAll+' approval')
    // if (!isApprovedForAll) {
    //   console.log('approving veTHE')
    //   const veTHEVault = new ethers.Contract(addr.veTHE, ABI_veNFT, vault)
    //   await veTHEVault.setApprovalForAll(addr.LiquidToken, true);
    // }
    // let tokenId = await veTHE.tokenOfOwnerByIndex(vault.address, 0)
    // console.log('redeeming tokenId: '+tokenId)
    // await LiquidToken.redeem(tokenId)
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