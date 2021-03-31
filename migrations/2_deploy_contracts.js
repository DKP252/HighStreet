const Dex = artifacts.require("DEX.sol");
const Token = artifacts.require("LumiToken.sol");

module.exports = async function (deployer, network) {
	let tokenAddress;
	if (network === "mainnet") {
		tokenAddress = "";
	} else {
		await deployer.deploy(Token, 330000);			// initialize reserve ratio for the token in ppm
		const token = await Token.deployed();
		tokenAddress = token.address;
	}
  await deployer.deploy(Dex, tokenAddress);
  const dex = await Dex.deployed();
};