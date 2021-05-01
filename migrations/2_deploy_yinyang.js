const Yin = artifacts.require("Yin");
const Yang = artifacts.require("Yang");

const router = "0x10ED43C718714eb63d5aA57B78B54704E256024E"
const testnet_router = "0x07d090e7FcBC6AFaA507A3441C7c5eE507C457e6"
const usd = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
const testnet_usd = "0xed24fc36d5ee211ea25a80239fb8c4cfd80f12ee"
const bnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
const testnet_bnb = "0x1e33833a035069f42d68D1F53b341643De1C018D"

module.exports = async function(deployer, network) {
  if(network == "testnet") {
    await deployer.deploy(Yin, testnet_router, testnet_usd)
    await deployer.deploy(Yang, testnet_router, testnet_bnb)
  } else {
    await deployer.deploy(Yin, router, usd)
    await deployer.deploy(Yang, router, bnb)
  }
};
