const Zen = artifacts.require("Zen");
const PancakeFactory = artifacts.require("PancakeFactory");
const TestCoinA = artifacts.require("TestCoinA");
const TestCoinB = artifacts.require("TestCoinB");

const factory = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"
const testnet_factory = "0xd417A0A4b65D24f5eBD0898d9028D92E3592afCC"
const usd = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
const testnet_usd = "0xed24fc36d5ee211ea25a80239fb8c4cfd80f12ee"
const bnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
const testnet_bnb = "0x1e33833a035069f42d68D1F53b341643De1C018D"

module.exports = async function(deployer, network) {
  if(network == "test" || network == "develop") {
    const coinA = await TestCoinA.deployed()
    const coinB = await TestCoinB.deployed()
    const test_factory = await PancakeFactory.deployed()
    const zen = await deployer.deploy(Zen, test_factory.address, coinA.address, coinB.address)
  } else if(network == "testnet") {
    const zen = await deployer.deploy(Zen, testnet_factory, testnet_usd, testnet_bnb)
  } else {
    const zen = await deployer.deploy(Zen, factory, usd, bnb)
  }
};
