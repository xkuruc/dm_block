require("@nomicfoundation/hardhat-toolbox");

require("solidity-coverage");

/** @type import('hardhat/config').HardhatUserConfig */
require("@nomiclabs/hardhat-ethers")
module.exports = {
  solidity: "0.8.17",
};


module.exports = {
  solidity: {
    compilers: [
      { version: "0.8.0", settings: { optimizer: { enabled: true, runs: 200 } } },
      { version: "0.8.9", settings: { optimizer: { enabled: true, runs: 200 } } }
    ]
  }
};