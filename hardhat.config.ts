import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as tenderly from "@tenderly/hardhat-tenderly";

//tenderly.setup({ automaticVerifications: true });

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {version: "0.8.28",},
      {version: "0.8.13",},
    ],
  },
  networks: {
    vbnb: {
      url: "https://virtual.binance.rpc.tenderly.co/fe598d34-c51e-4f7f-8415-987f1893f09c",
      chainId: 5656,
      currency: "VBNB"
    },
    vbnb2: {
      url: "https://virtual.binance.rpc.tenderly.co/beecce92-0264-4448-ab51-8913425814e5",
      chainId: 5656,
      currency: "VBNB"
    }
  },
  tenderly: {
    // https://docs.tenderly.co/account/projects/account-project-slug
    project: "project",
    username: "skzap",
  },
};

export default config;