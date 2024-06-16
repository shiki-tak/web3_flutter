const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const NftModule = buildModule("NftModule", (m) => {
  const nft = m.contract("NFT");

  return { nft };
});

module.exports = NftModule;