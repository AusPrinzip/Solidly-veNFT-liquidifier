const { ethers } = require("hardhat");

async function deployOne(contractName, ...args) {
  console.log("Deploying "+contractName+"...");
  const cf = await ethers.getContractFactory("LiquidToken");
  const c = await cf.deploy(...args);
  await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log("LiquidToken deployed to:", addr);
  return addr
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(deployer)
  console.log("Deploying contracts with account:", deployer.address);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", balance.toString());

  try {
    await deployOne("LiquidToken", "Liquid TOK", "liTOK", deployer.address)
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