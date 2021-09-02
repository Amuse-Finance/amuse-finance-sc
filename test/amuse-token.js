const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Amuse Token", async () => {
	beforeEach(async () => {
		const AmuseToken = await ethers.getContractFactory("AmuseToken");
		this.amuseToken = await AmuseToken.deploy();
	});

	describe("deployment", () => {
		it("should deploy token contract", async () => {
			expect(this.amuseToken.address).not.equal("");
			expect(this.amuseToken.address).not.equal(undefined);
			expect(this.amuseToken.address).not.equal(null);
		});

		// it("should set name properly", async () => {
		// 	expect(await this.amuseToken.name()).to.equal("Amuse Finance");
		// });

		// it("should set symbol properly", async () => {
		// 	expect(await this.amuseToken.symbol()).to.equal("AMD");
		// });

		// it("should set total")
	});
});
