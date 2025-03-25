const { ethers } = require("hardhat");
const addr = require('./addresses.json')

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
  const signers = await ethers.getSigners();
  const deployer = signers[0]
  const vault = signers[1]
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Vaulting with account:", vault.address)
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", balance.toString());

  try {
    console.log("LiquidToken", "liTOK", addr.veTHE, vault.address)
    await deployOne("LiquidToken", "LiquidToken", "liTOK", addr.veTHE, vault.address)
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