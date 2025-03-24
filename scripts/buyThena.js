// scripts/deploy.js
const { ethers } = require("hardhat");
const addr = require('./addresses.json')
const ABI_WBNB = require('./abi/WBNB.json')
const ABI_RouterV2 = require('./abi/RouterV2.json')
const ONE = "1000000000000000000"

async function main() {
  const [deployer] = await ethers.getSigners()
  console.log("Transacting as:", deployer.address)
  const balance = await ethers.provider.getBalance(deployer.address)
  console.log("Account balance:", ethers.formatEther(balance))

  // contracts
  const THE = new ethers.Contract(addr.THE, ABI_WBNB, deployer)
  const WBNB = new ethers.Contract(addr.WBNB, ABI_WBNB, deployer)
  const RouterV2 = new ethers.Contract(addr.RouterV2, ABI_RouterV2, deployer)
  

  try {
    // Check WBNB balance
    let balWBNB = await WBNB.balanceOf(deployer.address)
    console.log(ethers.formatEther(balWBNB) + ' WBNB')

    if (balWBNB < BigInt(ONE)) {
      // Wrap 1 BNB to 1 WBNB
      console.log('Wrapping 1 BNB')
      await WBNB.deposit({value: ONE})
    }

    // Check WBNB approval in RouterV2
    let allowance = await WBNB.allowance(deployer.address, addr.RouterV2)
    if (allowance < BigInt(ONE)) {
      console.log('Approving RouterV2 for 1 WBNB')
      await WBNB.approve(addr.RouterV2, ONE)
    }

    // Get quote WBNB -> THE
    let result = await RouterV2.getAmountOut(ONE, addr.WBNB, addr.THE)
    console.log('1 WBNB -> '+ethers.formatEther(result[0])+' THE')

    // Execute trade
    let routes = [
      {
        from: addr.WBNB,
        to: addr.THE,
        stable: false
      }
    ]
    let deadline = Math.floor(Date.now() / 1000) + 60 * 20
    await RouterV2.swapExactTokensForTokens(ONE, '0', routes, deployer.address, deadline)

    let balTHE = await THE.balanceOf(deployer.address)
    console.log('THE: '+ethers.formatEther(balTHE))
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