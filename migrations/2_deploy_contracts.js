// const Token = artifacts.require("ProductToken");
const Factory = artifacts.require("TokenFactory");

module.exports = async function (deployer, network, accounts ) {
	// await deployer.deploy(Token, 330000, 500, 3, web3.utils.toWei('9', 'ether'));			// initialize reserve ratio for the token in ppm, stand in for testing.
	// const token = await Token.deployed();
	await deployer.deploy(Factory, {from: accounts[0]});
	const factory = await Factory.deployed();
	let token = await factory.createToken("Kalon Tea", 330000, 500, 3, web3.utils.toWei('9', 'ether'), {from: accounts[0]});
	// let address = await factory.retrieveToken("Kalon Tea");		// this is how you retrieve token.	
};
