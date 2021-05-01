const Yin = artifacts.require("Yin");
const Yang = artifacts.require("Yang");
const YinDistributor = artifacts.require("YinDistributor");
const YangDistributor = artifacts.require("YangDistributor");

const usd = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
const bnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const bifi = "0xCa3F508B8e4Dd382eE878A314789373D80A5190A";
const yinv1 = "0xfDCFd19532ffc45772d99Ddb1d68748B3236e249";
const yangv1 = "0x13709bCC1964EEE12C8Dc799e8a81653bdFea5eB";
const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const testnet_wbnb = "0x1e33833a035069f42d68D1F53b341643De1C018D";
const testnet_bifi = "0xEC5dCb5Dbf4B114C9d0F65BcCAb49EC54F6A0867";
const testnet_usd = "0xed24fc36d5ee211ea25a80239fb8c4cfd80f12ee";
const testnet_usdc = "0x64544969ed7ebf5f083679233325356ebe738930";
const testnet_bnb = "0x1e33833a035069f42d68D1F53b341643De1C018D";
const startBlock = 6840400;

module.exports = async function (deployer, network) {
  await deployer.deploy(YinDistributor, Yin.address, startBlock);
  await deployer.deploy(YangDistributor, Yang.address, startBlock);
  const yin = await Yin.deployed();
  const yang = await Yang.deployed();
  await yin.setDistributor(YinDistributor.address);
  await yang.setDistributor(YangDistributor.address);
  await yin.excludeAccount(YinDistributor.address);
  await yang.excludeAccount(YangDistributor.address);
  const yinDistributor = await YinDistributor.deployed();
  const yangDistributor = await YangDistributor.deployed();
  if (network == "testnet") {
    await yinDistributor.add(32, 0, await yang.getPair(), true, 0);
    await yinDistributor.add(32, 10000, testnet_usd, true, 0);

    await yangDistributor.add(32, 0, await yin.getPair(), true, 0);
    await yangDistributor.add(32, 10000, testnet_wbnb, true, 0);
  } else {
    await yinDistributor.add(32, 0, await yang.getPair(), true, 0);
    await yinDistributor.add(32, 10000, yinv1, true, 0);

    await yangDistributor.add(32, 0, await yin.getPair(), true, 0);
    await yangDistributor.add(32, 10000, yangv1, true, 0);
  }
};
