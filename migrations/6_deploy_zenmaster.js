const ZenGarden = artifacts.require("ZenGarden");
const PeaceMaster = artifacts.require("PeaceMaster");
const Yin = artifacts.require("Yin");
const Yang = artifacts.require("Yang");
const Zen = artifacts.require("Zen");

const zenPerBlock = "1000000000000000000";
const startBlock = 6840400;

module.exports = async function (deployer) {
  await deployer.deploy(
    ZenGarden,
    zenPerBlock,
    startBlock,
    PeaceMaster.address,
    Zen.address
  );

  const zenGarden = await ZenGarden.deployed();
  const yin = await Yin.deployed();
  const yang = await Yang.deployed();
  const zen = await Zen.deployed();
  const zenPairs = await zen.getPairs();
  await zenGarden.add(450, await yin.getPair(), true, 0);
  await zenGarden.add(450, await yang.getPair(), true, 0);
  await zenGarden.add(50, zenPairs[0], true, 0);
  await zenGarden.add(50, zenPairs[1], true, 0);

  await (await PeaceMaster.deployed()).initialize(ZenGarden.address);
  await (await Zen.deployed()).transferOwnership(ZenGarden.address);
};
