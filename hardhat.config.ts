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
    virtual_bnb: {
      url: "https://virtual.binance.rpc.tenderly.co/7be63e7b-7cb4-4440-be04-50bab01713c2",
      chainId: 5656,
      currency: "VBNB"
    },
  },
  tenderly: {
    // https://docs.tenderly.co/account/projects/account-project-slug
    project: "project",
    username: "skzap",
  },
};

export default config;