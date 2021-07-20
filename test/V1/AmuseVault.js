const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");

const toWei = (_amount) =>
	ethers.utils.parseEther(parseFloat(_amount).toString());

const fromWei = (_amount) => ethers.utils.formatEther(_amount);

describe("Amuse Vault", () => {
	let deployer, admin, user1, user2;

	beforeEach(async () => {
		const amuseToken = await ethers.getContractFactory("AmuseToken");
		const amuseVault = await ethers.getContractFactory("AmuseVault");

		[deployer, admin, user1, user2] = await ethers.getSigners();

		this.token = await amuseToken.deploy();
		this.amuseVault = await amuseVault.deploy(this.token.address);

		// set AmuseVault
		await this.token.setAmuseVault(this.amuseVault.address);

		// this.uniswapV2Router = await ethers.getContractAt(
		// 	"IUniswapV2Router02",
		// 	await this.token.uniswapV2Router()
		// );

		// this.uniswapV2Factory = await ethers.getContractAt(
		// 	"IUniswapV2Factory",
		// 	await this.uniswapV2Router.factory()
		// );

		// // create liquidity pair
		// await this.uniswapV2Factory.createPair(
		// 	this.token.address,
		// 	await this.uniswapV2Router.WETH()
		// );

		// transfer some tokens to admin, user1, user2
		await this.token.connect(deployer).transfer(admin.address, toWei(1000));
		await this.token.connect(deployer).transfer(user1.address, toWei(1000));
		await this.token.connect(deployer).transfer(user2.address, toWei(1000));
	});

	describe("deployment", () => {
		it("should deploy contract properly", async () => {
			expect(this.token.address).not.equal(ZERO_ADDRESS);
			expect(this.token.address).not.equal(undefined);
			expect(this.token.address).not.equal(null);
			expect(this.token.address).not.equal("");
		});

		it("should set stakeTaxPercentage properly", async () => {
			const _stakeTaxPercentage = await this.amuseVault.stakeTaxPercentage();
			expect(_stakeTaxPercentage.toNumber()).to.equal(5);
		});

		it("should set unstakeTaxPercentage properly", async () => {
			const _unstakeTaxPercentage =
				await this.amuseVault.unstakeTaxPercentage();
			expect(_unstakeTaxPercentage.toNumber()).to.equal(10);
		});

		it("should set stakeDivisor properly", async () => {
			const _stakeDivisor = await this.amuseVault.stakeDivisor();
			expect(_stakeDivisor.toNumber()).to.equal(100);
		});

		it("should set valutRewardPercentage properly", async () => {
			const _valutRewardPercentage =
				await this.amuseVault.valutRewardPercentage();
			expect(_valutRewardPercentage.toNumber()).to.equal(1);
		});

		it("should set valutRewardDivisor properly", async () => {
			const _valutRewardDivisor = await this.amuseVault.valutRewardDivisor();
			expect(_valutRewardDivisor.toNumber()).to.equal(100);
		});
	});

	describe("Stake", () => {
		const _amount = toWei(100);
		let initialRewardPool;
		let _reciept;

		beforeEach(async () => {
			initialRewardPool = fromWei(await this.token.rewardsPool());

			// approve tokens to stake
			await this.token
				.connect(user1)
				.approve(this.amuseVault.address, toWei(_amount));
			// stake tokens to pool
			_reciept = await this.amuseVault.connect(user1).stake(_amount);
		});

		it("should stake tokens properly", async () => {
			const { user, stakes } = await this.amuseVault.stakes(user1.address);
			expect(user).to.equal(user1.address);
			expect(fromWei(stakes)).to.equal((95).toFixed(1));
		});

		it("should  validate stakes", async () => {
			expect(fromWei(await this.token.rewardsPool())).to.equal(
				(parseFloat(initialRewardPool) + 5).toFixed(1)
			);
		});
	});

	describe("Unstake", () => {
		const _amount = toWei(100);
		let initialRewardPool;
		let initialTokenBalance;
		let _reciept;

		beforeEach(async () => {
			// approve tokens to stake
			await this.token
				.connect(user1)
				.approve(this.amuseVault.address, toWei(_amount));
			// stake tokens to pool
			await this.amuseVault.connect(user1).stake(_amount);
			initialRewardPool = fromWei(await this.token.rewardsPool());
			initialTokenBalance = fromWei(await this.token.balanceOf(user1.address));
			_reciept = await this.amuseVault.connect(user1).unstake(toWei(20));
		});

		it("should unstake tokens properly", async () => {
			const { stakes } = await this.amuseVault.stakes(user1.address);
			expect(fromWei(stakes)).to.equal((75).toFixed(1));
		});

		it("should  validate stakes", async () => {
			expect(fromWei(await this.token.rewardsPool())).to.equal(
				(parseFloat(initialRewardPool) + 2.45).toFixed(2)
			);

			expect(fromWei(await this.token.balanceOf(user1.address))).to.equal(
				initialRewardPool + (17.5).toFixed(2)
			);
		});
	});
});
