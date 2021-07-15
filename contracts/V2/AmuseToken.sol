// SPDX-License-Identifier: MIT 
pragma solidity 0.8.5;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../interface/IUniswapV2Factory.sol";
import "../interface/IUniswapV2Router02.sol";

contract AmuseToken1 is ERC20, ERC20Permit, ERC20Burnable, Ownable {
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;

    uint256 public cashbackPercentage;
    uint256 public cashbackInterval;
    uint256 public taxPercentage;
    uint256 public taxDivisor;
    uint8 public activate;
    uint256 private averageGasPrice;

    uint256 public rewardPool;
    address public AmusedVault;
    address public admin;

    mapping(address => bool) public excluded;
    mapping(address => Cashback) public cashbacks;
    mapping(address => address) public referrers;

    struct Cashback {
        address user;
        uint256 totalClaimedCashback;
        uint256 timestamp;
    }

    event CashBack(address user, uint256 amount, uint256 timestamp);
    event Referral(address indexed user, address indexed referrer, uint256 timestamp);
    event ReferralReward(address indexed user, address indexed referrer, uint256 purchased, uint256 reward, uint256 timestamp);
    event GasRefund(address indexed user, uint256 amount, uint256 timestamp);
    event AmuseVault(address indexed vault, uint256 timestamp);
    event AmuseVaultMint(address indexed vault, uint256 amount, uint256 timestamp);
    event RewardPoolSeeded(address indexed account, uint256 indexed amountSeeded, uint256 timestamp);

    constructor() ERC20("Amuse Finance", "AMD") ERC20Permit("Amuse Finance") {
        taxPercentage = 10;
        taxDivisor = 100;

        cashbackPercentage = 1;
        cashbackInterval = 24 hours;
        averageGasPrice = 7 gwei;

        uint256 _initalSupply = 20_000_000 ether;
        uint256 _deployerAmount = (_initalSupply * 70) / 100;

        _mint(_msgSender(), _deployerAmount);
        _mint(address(this),  _initalSupply - _deployerAmount);
        rewardPool =  _initalSupply - _deployerAmount;


        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

        excluded[address(this)] = true;
        excluded[address(uniswapV2Router)] = true;
        excluded[address(uniswapV2Factory)] = true;

        cashbacks[_msgSender()] = Cashback(_msgSender(), 0, block.timestamp);
    }

    receive() external payable { 
        revert();
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        uint256 _initalBalance = super.balanceOf(account);
        uint256 _cashback = calculateCashback(account);
        uint256 _finalBalance = _initalBalance + _cashback;
        return _finalBalance;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        (uint256 _finalAmount, uint256 _taxAmount) = calculateTax(recipient, amount);
        super._transfer(sender, recipient, _finalAmount);
        super._transfer(sender, address(this), _taxAmount);
        // collect tax and distribute
        _distibuteTax(_taxAmount);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);

        // calculate referrer's rewards and credit address
        uint256 _referrerRewards = _calculateReferrerRewards(amount);
        _transferReferrerFee(_msgSender(), recipient, amount, _referrerRewards);

        // Note:: Gas refunds is only applicable to all AMD buy actions from users
        _refundGas(recipient);
        return true;
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override { 
        // settle eligible cashback earned
        _claimCashback(from);
        _claimCashback(to);
    }

    function _afterTokenTransfer(address from, address to, uint256) internal virtual override {
        // Set Initial Cashback state when a new user purchases AMD token
        if(balanceOf(from) > 0 && cashbacks[from].timestamp == 0) 
            cashbacks[from] = Cashback(from, 0, block.timestamp);

        if(balanceOf(to) > 0 && cashbacks[to].timestamp == 0) 
            cashbacks[to] = Cashback(to, 0, block.timestamp);

        // reset lastClaimedCashback if balance <= 0
        _resetLastClaimedTime(from);
        _resetLastClaimedTime(to);
    }

    // Untracked
    function calculateTax(address to, uint256 amount) public view returns(uint256 finalAmount, uint256 taxAmount) {
        if(taxPercentage == 0 || excluded[_msgSender()] || to == AmusedVault) return(amount, 0);

        // calculate transaction fees
        taxAmount = (amount * taxPercentage) / taxDivisor;
        finalAmount = amount - taxAmount;
        return (finalAmount, taxAmount);
    }
    
    function _distibuteTax(uint256 _tax) internal returns(uint8) {
        if(_tax == 0) return 0;
        uint256 _splitedTax = _tax / 4;

        // 50% of the collected tax is added into rewardspool
        rewardPool += (_splitedTax * 2);
        // 25% of the collected tax is burnt from the totalsupply
        _burn(address(this), _splitedTax);
        // the remaining 25% tax is issued to the refferer of the current buyer else it is added into the "rewardPool"
        return 1;
    }

    function exclude(address _account, bool _status) external onlyOwner {
        excluded[_account] = _status;
    }

    function _isContract(address account) internal view returns(bool) {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    function setActivate() external onlyOwner {
        // This function is invoked after LP has been properly added into the pool
        if(activate == 0) activate = 1;
        else activate = 0;
    }

    function setTaxPercentage(uint256 _amount, uint256 _divisor) external onlyOwner {
        taxPercentage = _amount;
        taxDivisor = _divisor;
    }

    function  setCashbackInterval(uint256 _interval) external onlyOwner {
        cashbackInterval = _interval;
    }

    function setCashbackPercentage(uint256 _percentage) external onlyOwner {
        cashbackPercentage = _percentage;
    }

    function setAmuseVault(address _amuseVault) external onlyOwner {
        require(_isContract(_amuseVault), "AmuseToken: Not a valid contract address");
        /*
            Note:: Sets AmuseVault Contract address & also
            excludes AmuseVault Contract from paying tax / receiving cashback rewards
        */
        AmusedVault = _amuseVault;
        excluded[_amuseVault] = true;
        emit AmuseVault(_amuseVault, block.timestamp);
    }

    function amuseVaultMint(uint256 _amount) external returns(uint8) {
        /*
            Note:: Only AmuseVault Contract can call this funtion. 
            Externally owned address call is rejected 
        */
        require(_msgSender()  == AmusedVault, "AmuseToken: Authentication failed");
        if(_amount == 0) return 0;
        _mint(AmusedVault, _amount);
        emit AmuseVaultMint(_msgSender(), _amount, block.timestamp);
        return 1;
    }

    function fundRewardsPool(uint256 _amount) external {
        _transfer(_msgSender(), address(this), _amount);
        rewardPool += _amount;
        emit RewardPoolSeeded(_msgSender(), _amount, block.timestamp);
    }

    function setAdmin(address _newAdmin) external onlyOwner {
        require(_newAdmin != address(0), "AmuseToken: New Admin can not be zero address");
        admin = _newAdmin;
    }

    function withdrawETH(uint256 _amount) external onlyOwner {
        (bool _success,) = payable(_msgSender()).call{ value: _amount }("");
        require(_success, "AmuseToken: ETHER withdrawal failed");
    }

    function setAverageGasPrice(uint256 _newAverageGasPrice) external onlyOwner {
        require(_msgSender() == admin, "AmuseToken: Action revoked");
        averageGasPrice = _newAverageGasPrice;
        _refundGas(_msgSender());
    }

    function sync() external {
        // sync stray tokens into the rewardPool
        uint256 _contractBalance = balanceOf(address(this));
        uint256 _diff = _contractBalance - rewardPool;
        rewardPool += _diff;
    }

    // Start Cashback Logics
    function calculateDailyCashback(address _recipient) public view returns(uint256) {
        if(super.balanceOf(_recipient) == 0) return 0;
        uint256 _balance = super.balanceOf(_recipient);
        uint256 _rewards = (_balance * cashbackPercentage) / 100;
        return _rewards;
    }

    function calculateCashback(address _recipient) public view returns(uint256 _rewards) {
        if(
            super.balanceOf(_recipient) == 0 || 
            cashbacks[_recipient].timestamp == 0 || 
            excluded[_recipient] ||
            _recipient == getPair()
        ) return 0;
        uint256 _lastClaimed = cashbacks[_recipient].timestamp;

        uint256 _unclaimedDays = (block.timestamp - _lastClaimed) / cashbackInterval;
        _rewards = _unclaimedDays * calculateDailyCashback(_recipient);
        return _rewards;
    }

    function _claimCashback(address _recipient) internal returns(uint8) {
        if(calculateCashback(_recipient) == 0) return 0;
        uint256 _rewards = calculateCashback(_recipient);
        uint256 _totalClaimedCashback =  cashbacks[_recipient].totalClaimedCashback + _rewards;

        cashbacks[_recipient] = Cashback(_recipient, _totalClaimedCashback, block.timestamp);
        _transferCashbackReward(_recipient, _rewards);
        emit CashBack(_recipient, _rewards, block.timestamp);
        return 1;
    }

    function _transferCashbackReward(address _recipient, uint256 _rewards) internal {
        if(rewardPool < _rewards) {
            uint256 _diff = _rewards - rewardPool;
            _mint(address(this), _diff);
            rewardPool += _diff;
        }
        rewardPool -= _rewards;
        _transfer(address(this), _recipient, _rewards);
    }

    function _resetLastClaimedTime(address _account) private returns(uint8) {
        if(super.balanceOf(_account) > 0) return 0;
        cashbacks[_account].timestamp = 0;
        return 1;
    }
    // End claimable cashback

    // Referral Logic
    function addReferrer(address _referrer) external {
        require(referrers[_msgSender()] == address(0), "AmuseToken: Referrer has already been registered");
        require(_msgSender() != _referrer, "AmuseToken: Can not register self as referrer");
        require(balanceOf(_msgSender()) != 0, "AmuseToken: Balance must be greater than zero to register a referrer");
        require(!_isContract(_referrer), "AmuseToken: Referrer can not be contract address");

        referrers[_msgSender()] = _referrer;
        emit Referral(_msgSender(), _referrer, block.timestamp);
    }

    function _calculateReferrerRewards(uint256 _amount) private view returns(uint256 _referralTaxPercentage) {
        uint256 _tax = (_amount * taxPercentage)  / 100;
        _referralTaxPercentage = (_tax * 25) / 100;
        return _referralTaxPercentage;
    }

    function _transferReferrerFee(address _pair, address _buyer, uint256 _purchased, uint256 _rewards) internal returns(uint8) {
        if(referrers[_buyer] != address(0) && _pair == getPair()) {
            _transfer(address(this), referrers[_buyer], _rewards);
            emit ReferralReward(_buyer, referrers[_buyer], _purchased, _rewards, block.timestamp);
            return 1;
        }
        // adds referral rewards to rewardpool if referrer doesn't exist
        rewardPool += _rewards;
        return 0;
    }
    // End Referral Logics

    // Gas Refund Logics
    function _refundGas(address _user) internal returns(uint8) {
        if(activate == 0 || _msgSender() != getPair()) return 0;
        uint256 _gasUsed = averageGasPrice * 50000;
        uint256[] memory amounts = getAmountsOut(uniswapV2Router.WETH(), address(this), _gasUsed);
        _mint(_user, amounts[1]);
        emit GasRefund(_user, amounts[0], block.timestamp);
        return 1;
    }
    // End Gas Refund Logics

    // Uniswap logics
    function getPair() public view returns(address pair) {
        pair = uniswapV2Factory.getPair(address(this), uniswapV2Router.WETH());
        return pair;
    }
    
    function getAmountsOut(address token1, address token2, uint256 _amount) public view returns(uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token2;
        amounts = uniswapV2Router.getAmountsOut(_amount, path);
        return amounts;
    }
}