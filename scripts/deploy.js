const { ethers } = require("hardhat");
const addr = require('./addresses.json')

async function deployOne(contractName, ...args) {
  console.log("Deploying "+contractName+"...");
  const cf = await ethers.getContractFactory(contractName);
  const c = await cf.deploy(...args);
  await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log(contractName + " deployed to:", addr);
  return c
}

async function main() {
  const signers = await ethers.getSigners();
  const deployer = signers[0]
  const rewardDistributor = signers[1]
  const voter = signers[2]
  const lockingYear = 2;

  console.log("Deploying contracts with account:", deployer.address);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", balance.toString());

  try {
    console.log(addr.THE, addr.veTHE, voter.address, rewardDistributor.address, addr.ExternalDistributor, lockingYear)
    const strategy = await deployOne("SolidlyStrategy", addr.THE, addr.veTHE, voter.address, rewardDistributor.address, addr.ExternalDistributor, lockingYear)
    console.log("LiquidToken", "LiquidToken", "liTOK", addr.veTHE, await strategy.getAddress())
    const liquidToken = await deployOne("LiquidToken", "LiquidToken", "liTOK", addr.veTHE, await strategy.getAddress())
    strategy.connect(voter)
    await strategy.setLiquidToken(await liquidToken.getAddress())

  } catch (error) {
    console.error("Error during deployment:", error);
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