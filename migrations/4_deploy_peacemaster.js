const PeaceMaster = artifacts.require("PeaceMaster");
const Yin = artifacts.require("Yin");
const Yang = artifacts.require("Yang");
const WBNB = artifacts.require("WBNB");
const PancakeRouter = artifacts.require("PancakeRouter");

const router = "0x10ED43C718714eb63d5aA57B78B54704E256024E"
const testnet_router = "0x07d090e7FcBC6AFaA507A3441C7c5eE507C457e6"
const usd = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
const testnet_usd = "0xed24fc36d5ee211ea25a80239fb8c4cfd80f12ee"

const startTime = "2021-04-24T11:30:00"

module.exports = async function(deployer, network) {
  if(network == "test" || network == "develop") {
    // 10mn Epochs
    const test_wbnb = await WBNB.deployed()
    const test_router = await PancakeRouter.deployed()
    await deployer.deploy(PeaceMaster, 10*60, Yin.address, Yang.address, test_wbnb.address, test_router.address)
  } else if(network == "testnet") {
    // 10mn Epochs
    const start = Math.trunc((Date.parse("2021-04-24T08:00:00").valueOf() / 1000))
    await deployer.deploy(PeaceMaster, start, 10*60, Yin.address, Yang.address, testnet_usd, testnet_router)
  } else {
    // 1 day epochs
    const start = Math.trunc((Date.parse(startTime).valueOf() / 1000))
    await deployer.deploy(PeaceMaster, start, 24*60*60, Yin.address, Yang.address, usd, router)
  }
  /*const yin = await Yin.deployed()
  const yang = await Yang.deployed()
  await yin.transferOwnership(PeaceMaster.address)
  await yang.transferOwnership(PeaceMaster.address)*/
};
