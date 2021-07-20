// SPDX-License-Identifier: MIT 
pragma solidity 0.8.5;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interface/IUniswapV2Factory.sol";
import "../interface/IUniswapV2Router02.sol";
import "../interface/IAmused.sol";

import "hardhat/console.sol";

contract AmuseVault is Ownable, ReentrancyGuard {
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;
    IAmused public AmuseToken;

    uint256 public stakeTaxPercentage;
    uint256 public unstakeTaxPercentage;
    uint256 public stakeDivisor;
    
    uint256 public valutRewardPercentage;
    uint256 public valutRewardDivisor;
    uint256 public vaultRewardInterval;

    uint256 public totalTokenLocked;

    mapping(address => Stake) public stakes;

    struct Stake {
        address user;
        uint256 stakes;
        uint256 timestamp;
    }

    event STAKE(address indexed user, uint256 stakes, uint256 timestamp);
    event UNSTAKE(address indexed user, uint256 amount, uint256 tokenValue, uint256 ethValue, uint256 timestamp);

    constructor(IAmused _amusedToken) {
        AmuseToken = _amusedToken;

        stakeTaxPercentage = 5;
        unstakeTaxPercentage = 10;
        stakeDivisor = 100;

        valutRewardPercentage = 1;
        valutRewardDivisor = 100;
        vaultRewardInterval = 1 minutes;

        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Factory = IUniswapV2Factory(uniswapV2Router.factory());
    }

    receive() external payable { revert(); }
    
    function stake(uint256  _amount) external {
        console.log("Initial rewardsPool: %s", AmuseToken.rewardsPool() / 1 ether);

        require(stakes[_msgSender()].stakes == 0, "AmuseVault: Active stakes found");
        AmuseToken.transferFrom(_msgSender(), address(this), _amount);        

        (uint256 _finalAmount, uint256 _taxAmount) = _calculateTax(_amount, stakeTaxPercentage);
        totalTokenLocked += _finalAmount;
        stakes[_msgSender()] = Stake(_msgSender(), _finalAmount, block.timestamp);

       // inject tax into AMD rewardspool
        AmuseToken.transfer(address(AmuseToken), _taxAmount);
        AmuseToken.sync();

        console.log("Amount of token staked: %s", _amount / 1 ether);
        console.log("Final amount staked: %s", _finalAmount / 1 ether);
        console.log("Final rewardsPool: %s", AmuseToken.rewardsPool() / 1 ether);
        console.log("Contract AND balalnce: %s", AmuseToken.balanceOf(address(this)) / 1 ether);

        emit STAKE(_msgSender(), _amount, block.timestamp);
    }

    function unstake(uint256 _amount) external nonReentrant {
        require(stakes[_msgSender()].stakes > 0, "AmuseVault: No active stake found");
        require(_amount > 0, "AmuseVault: unstaked amount must be greater than zero");
        require(_amount <= stakes[_msgSender()].stakes, "AmuseVault: amount is greater than staked balance");

        (uint256 _finalAmount, uint256 _taxAmount) = _calculateTax(_amount, unstakeTaxPercentage);
        (uint256 _tokenValueEarned, uint256 _ethValueEarned) = calculateStakeRewards(_msgSender(), _amount);

        // mint the rewards earned from staking to contract and swap for ETH later
        AmuseToken.amuseVaultRewards(_tokenValueEarned);
        // _swapExactTokensForETH(_tokenValueEarned);

        totalTokenLocked -= _amount;
        uint256 _finalStakedBalance = stakes[_msgSender()].stakes - _amount;

        stakes[_msgSender()] = Stake(_msgSender(), _finalStakedBalance, stakes[_msgSender()].timestamp);
        // Set the timestamp to "block.timestamp" only if the "staked balance" is equal to ZERO
        if(stakes[_msgSender()].stakes == 0) stakes[_msgSender()].timestamp = block.timestamp;

        // inject tax into AMD rewardspool
        AmuseToken.transfer(address(AmuseToken), _taxAmount);
        AmuseToken.sync();

        // transfer remaining locked tokens
        AmuseToken.transfer(_msgSender(), _finalAmount);

        // transfer ETH rewards
        (bool _success,) = payable(_msgSender()).call{ value: _ethValueEarned }("");
        require(_success, "AmuseVault: ETH rewards transfer failed");
        emit UNSTAKE(_msgSender(), _amount, _tokenValueEarned, _ethValueEarned,  block.timestamp);
    }

    function calculateStakeRewards(address _account, uint256 _amount) public view returns(uint256 _tokenValueEarned, uint256 _ethValueEarned) {
        if(
            stakes[_account].stakes == 0 || 
            _amount == 0 || 
            _amount > stakes[_account].stakes
        ) return(0, 0);
        uint256[] memory amounts;

        uint256 _stakedDays = (block.timestamp - stakes[_account].timestamp) / vaultRewardInterval;
        uint256 _rewardsPerDay = (_amount * valutRewardPercentage) / valutRewardDivisor;
        _tokenValueEarned = _stakedDays * _rewardsPerDay;   

        // return if "_tokenValueEarned" is equal to ZERO
        if(_tokenValueEarned == 0) return (0, 0);

        amounts = getAmountsOut(address(AmuseToken), uniswapV2Router.WETH(), _tokenValueEarned);
        return (_tokenValueEarned, amounts[1]);
    }

    function _calculateTax(uint256 _amount, uint256 _tax) internal view returns(uint256 _finalAmount, uint256 _taxAmount) {
        // calculate tax fees for the given input
        _taxAmount = (_amount * _tax) / stakeDivisor;
        _finalAmount = _amount - _taxAmount;
        return(_finalAmount, _taxAmount);
    }

    function setTax(uint256 _stakeTaxPercentage, uint256 _unstakeTaxPercentage, uint256 _stakeDivisor) external onlyOwner {
        stakeTaxPercentage = _stakeTaxPercentage;
        unstakeTaxPercentage = _unstakeTaxPercentage;
        stakeDivisor = _stakeDivisor;
    }
    
    function setValutReward(uint256 _percentage, uint256 _divisor, uint256 _interval) external onlyOwner {
        valutRewardPercentage = _percentage;
        valutRewardDivisor = _divisor;
        vaultRewardInterval = _interval;
    }

    function _swapExactTokensForETH(uint256 _tokenAmount) internal returns(uint8) {
        if(_tokenAmount == 0) return 0;
        address[] memory path = new address[](2);
        path[0] = address(AmuseToken);
        path[1] = uniswapV2Router.WETH();
        // approve tokens to be spent
        AmuseToken.approve(address(uniswapV2Router), _tokenAmount);
        // swap token => ETH
        uniswapV2Router.swapExactTokensForETH(_tokenAmount, 0, path, address(this), block.timestamp);
        return 1;
    }

    function getAmountsOut(address token1, address token2, uint256 _amount) internal view returns(uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token2;
        amounts = uniswapV2Router.getAmountsOut(_amount, path);
        return amounts;
    }
}