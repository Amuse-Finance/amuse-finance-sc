const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { time } = require("@openzeppelin/test-helpers");

const toWei = (_amount) =>
	ethers.utils.parseEther(parseFloat(_amount).toString());

const fromWei = (_amount) => ethers.utils.formatEther(_amount);

const wait = async () =>
	setTimeout(() => {
		resolve("");
	}, 5000);

describe("AmuseToken", () => {
	let deployer;
	let admin;
	let user1;
	let user2;

	beforeEach(async () => {
		const amuseToken = await ethers.getContractFactory("AmuseToken1");
		this.token = await amuseToken.deploy();

		this.uniswapV2Router = await ethers.getContractAt(
			"IUniswapV2Router02",
			await this.token.uniswapV2Router()
		);

		this.uniswapV2Factory = await ethers.getContractAt(
			"IUniswapV2Factory",
			await this.uniswapV2Router.factory()
		);

		// create liquidity pair
		await this.uniswapV2Factory.createPair(
			this.token.address,
			await this.uniswapV2Router.WETH()
		);

		[deployer, admin, user1, user2] = await ethers.getSigners();
	});

	describe("deployment", () => {
		it("should deploy contract properly", async () => {
			expect(this.token.address).not.equal(ZERO_ADDRESS);
			expect(this.token.address).not.equal(undefined);
			expect(this.token.address).not.equal(null);
			expect(this.token.address).not.equal("");
		});

		it("should set name properly", async () => {
			expect(await this.token.name()).to.equal("Amuse Finance");
		});

		it("should set symbol properly", async () => {
			expect(await this.token.symbol()).to.equal("AMD");
		});

		it("should set decimals properly", async () => {
			expect(await this.token.decimals()).to.equal(18);
		});

		it("should set totalSupply properly", async () => {
			expect(await this.token.totalSupply()).to.equal(toWei(20_000_000));
		});

		it("should set balance of deployer properly", async () => {
			expect(await this.token.balanceOf(deployer.address)).to.equal(
				toWei(14_000_000)
			);
		});

		it("should returns pair address", async () => {
			const _pair = await this.token.getPair();
			expect(_pair).not.equal(ZERO_ADDRESS);
			expect(_pair).not.equal(undefined);
			expect(_pair).not.equal(null);
			expect(_pair).not.equal("");
		});

		it("should set tax percentage properly", async () => {
			expect(await this.token.taxPercentage()).to.equal(
				ethers.BigNumber.from("10")
			);
		});
	});

	describe("transfer", async () => {
		beforeEach(async () => {
			await this.token.connect(deployer).transfer(user1.address, toWei(10000));
		});

		it("should transfer token properly", async () => {
			expect(await this.token.balanceOf(user1.address)).to.equal(toWei(9_000));
		});

		it("should reject if amount is greater than sender's balance", async () => {
			try {
				await this.token.connect(user2).transfer(user1.address, toWei(100));
			} catch (error) {
				assert(error.toString().includes(""));
				return;
			}
			assert(false);
		});
	});

	describe("calculateTax", () => {
		it("should calculate tax properly", async () => {
			const { finalAmount, taxAmount } = await this.token.calculateTax(
				deployer.address,
				toWei(1000)
			);
			expect(fromWei(finalAmount)).to.equal("900.0");
			expect(fromWei(taxAmount)).to.equal("100.0");
		});
	});

	describe("exclude", () => {
		beforeEach(async () => {
			await this.token.connect(deployer).exclude(user1.address, true);
		});

		it("should exclude account", async () => {
			const status = await this.token.excluded(user1.address);
			expect(status).to.equal(true);
		});

		it("should reject if caller is the the deployer", async () => {
			try {
				await this.token.connect(user1).exclude(user1.address, false);
			} catch (error) {
				assert(error.toString().includes("Ownable: caller is not the owner"));
				return;
			}
			assert(false);
		});
	});

	describe("_claimCashback", () => {
		beforeEach(async (done) => {
			// reset the cashbackInterval to 5s
			await this.token.connect(deployer).setCashbackInterval(5);
			// send some tokens to user1
			await this.token
				.connect(deployer)
				.transfer(user1.address, toWei(100_000));

			await wait();
			done();
		});

		// it("should increment user balance by 1%", async () => {
		// 	console.log(fromWei(await this.token.balanceOf(user1.address)));
		// });
	});
});
