const { ethers, upgrades } = require("hardhat");

const main = async () => {
	const AmuseToken = await ethers.getContractFactory("AmuseToken");
	const AmuseExchange = await ethers.getContractFactory("AmuseExchange");

	const amuseToken = await upgrades.deployProxy(AmuseToken, []);
	const amuseExchange = await upgrades.deployProxy(AmuseExchange, [
		amuseToken.address,
	]);
	console.log("done");
};
main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
