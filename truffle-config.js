const HDWalletProvider = require('@truffle/hdwallet-provider');
const fs = require('fs');
const mnemonic = fs.readFileSync(".pkey").toString().trim();

module.exports = {
  // Uncommenting the defaults below
  // provides for an easier quick-start with Ganache.
  // You can also follow this format for other networks;
  // see <http://truffleframework.com/docs/advanced/configuration>
  // for more details on how to specify configuration options!
  //
  networks: {
    /*development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
    },*/
    bsc: {
      provider: () => new HDWalletProvider(mnemonic, `https://bsc-dataseed1.binance.org`),
      network_id: 56,
      confirmations: 10,
      timeoutBlocks: 200,
      skipDryRun: true,
      gas: 30000000,
      gasPrice: 5000000000,
    },
    testnet: {
      provider: () => new HDWalletProvider(mnemonic, `https://data-seed-prebsc-2-s1.binance.org:8545/`),
      network_id: 97,
      confirmations: 0,
      timeoutBlocks: 200,
      skipDryRun: true,
      gasPrice: 5000000000,
    },
    develop: {
      network_id: "*",
      accounts: 5,
      defaultEtherBalance: 500,
      blockTime: 1,
      gas: 30000000
    }
  },
  compilers: {
    solc: {
      version: "^0.6.12", // A version or constraint - Ex. "^0.5.0"
      parser: "solcjs", // Leverages solc-js purely for speedy parsing
      settings: {
        optimizer: {
          enabled: true,
          runs: 9999, // Optimize for how many times you intend to run the code
        },
        evmVersion: "istanbul", // Default: "istanbul"
      },
    },
  },
};
