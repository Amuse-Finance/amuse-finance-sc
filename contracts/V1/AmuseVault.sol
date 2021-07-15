// SPDX-License-Identifier: MIT 
pragma solidity 0.8.5;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/IUniswapV2Factory.sol";
import "../interface/IUniswapV2Router02.sol";
import "../interface/IAmused.sol";

contract AmuseVault is Ownable, ReentrancyGuard {
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;

    IAmused public AmusedToken;
    uint256 public taxPercentage;
    uint256 public valutRewardPercentage;
    uint256 public totalTokenLocked;
    uint256 public rewardsInterval;
    uint256 private _liquidityRewardPool;

    mapping(address => Stake) public stakes;

    struct Stake {
        address user;
        uint256 stakes;
        uint256 timestamp;
    }

    event STAKE(address indexed user, uint256 stakes, uint256 timestamp);
    event UNSTAKE(address indexed user, uint256 amount, uint256 tokenValue, uint256 ethValue, uint256 timestamp);
    event LiquidityInjected(uint amountToken, uint amountETH, uint liquidity, uint256 timestamp);

    constructor(IAmused _amusedToken) {
        AmusedToken = _amusedToken;
        taxPercentage = 5;
        valutRewardPercentage = 1;
        rewardsInterval = 5 minutes;
        /* 
            instantiate uniswapV2Router & uniswapV2Factory
            uniswapV2Router address: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
            pancakeswapV2Router address: 0xD99D1c33F9fC3444f8101754aBC46c52416550D1
        */
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Factory = IUniswapV2Factory(uniswapV2Router.factory());
    }

    receive() external payable {  }
    
    function stake(uint256  _amount) external {
        require(stakes[_msgSender()].stakes == 0, "AmuseVault: Active stakes found");

        AmusedToken.transferFrom(_msgSender(), address(this), _amount);
        
        (uint256 _finalAmount, uint256 _taxAmount) = _tax(_amount);
        totalTokenLocked += _finalAmount;
        stakes[_msgSender()] = Stake(_msgSender(), _finalAmount, block.timestamp);

        // inject tax into liquidity
        _liquidityRewardPool += _taxAmount;
        _addLiquity();
        emit STAKE(_msgSender(), _amount, block.timestamp);
    }

    function unstake(uint256 _amount) external nonReentrant {
        require(stakes[_msgSender()].stakes > 0, "AmuseVault: No active stake found");
        require(_amount > 0, "AmuseVault: unstaked amount must be greater than zero");
        require(_amount <= stakes[_msgSender()].stakes, "AmuseVault: amount is greater than staked balance");

        (uint256 _finalAmount, uint256 _taxAmount) = _tax(_amount);
        (uint256 _tokenValueEarned, uint256 _ethValueEarned) = calculateStakeRewards(_msgSender(), _amount);

        // mint the rewards earned from staking to contract and swap for ETH later
        AmusedToken.amuseVaultMint(_tokenValueEarned);
        _swapExactTokensForETH(_tokenValueEarned);

        totalTokenLocked -= _amount;
        uint256 _finalStakedBalance = stakes[_msgSender()].stakes - _amount;

        stakes[_msgSender()] = Stake(_msgSender(), _finalStakedBalance, stakes[_msgSender()].timestamp);
        // Set the timestamp to "block.timestamp" only if the "staked balance" is equal to ZERO
        if(stakes[_msgSender()].stakes == 0) stakes[_msgSender()].timestamp = block.timestamp;

        // inject tax into liquidity
        _liquidityRewardPool += _taxAmount;
        _addLiquity();

        // transfer remaining locked tokens
        AmusedToken.transfer(_msgSender(), _finalAmount);

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

        uint256 _stakedDays = (block.timestamp - stakes[_account].timestamp) / rewardsInterval;
        uint256 _rewardsPerDay = (_amount * valutRewardPercentage) / 100;
        _tokenValueEarned = _stakedDays * _rewardsPerDay;   

        // return if "_tokenValueEarned" is equal to ZERO
        if(_tokenValueEarned == 0) return (0, 0);

        amounts = getAmountsOut(address(AmusedToken), uniswapV2Router.WETH(), _tokenValueEarned);
        return (_tokenValueEarned, amounts[1]);
    }

    function _tax(uint256 _amount) internal view returns(uint256 _finalAmount, uint256 _taxAmount) {
        // calculate tax fees for the given input
        _taxAmount = (_amount * taxPercentage) / 100;
        _finalAmount = _amount - _taxAmount;
        return(_finalAmount, _taxAmount);
    }

    function setTaxPercentage(uint256 _amount) external onlyOwner {
        taxPercentage = _amount;
    }
    
    function setValutRewardPercentage(uint256 _percentage) external onlyOwner {
        valutRewardPercentage = _percentage;
    }

    function setRewardsInterval(uint _interval) external onlyOwner {
        rewardsInterval = _interval;
    }

    function _addLiquity() internal returns(uint8) {
        if(_liquidityRewardPool == 0) return 0;
        address[] memory path = new address[](2);
        uint256[] memory amounts;

        path[0] = address(AmusedToken);
        path[1] = uniswapV2Router.WETH();

        uint256 _splitAmount = _liquidityRewardPool / 2;
        amounts = getAmountsOut(address(AmusedToken), uniswapV2Router.WETH(), _splitAmount);

        // approve tokens to be spent
        AmusedToken.approve(address(uniswapV2Router), _liquidityRewardPool);
        // Swap token for ETH
        uniswapV2Router.swapExactTokensForETH(_splitAmount, 0, path, address(this), block.timestamp);
        // add Liquidity
        (uint _amountToken, uint _amountETH, uint _liquidity) = uniswapV2Router.addLiquidityETH{ value: amounts[1] }(
            address(AmusedToken),
            _splitAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
        _liquidityRewardPool -= (_splitAmount + _amountToken);
        emit LiquidityInjected(_amountToken, _amountETH, _liquidity, block.timestamp);
        return 1;
    }

    function _swapExactTokensForETH(uint256 _tokenAmount) internal returns(uint8) {
        if(_tokenAmount == 0) return 0;
        address[] memory path = new address[](2);
        path[0] = address(AmusedToken);
        path[1] = uniswapV2Router.WETH();
        // approve tokens to be spent
        AmusedToken.approve(address(uniswapV2Router), _tokenAmount);
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