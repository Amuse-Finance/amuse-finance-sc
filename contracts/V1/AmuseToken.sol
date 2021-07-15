// SPDX-License-Identifier: MIT 
pragma solidity 0.8.5;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "../interface/IUniswapV2Factory.sol";
import "../interface/IUniswapV2Router02.sol";

contract AmuseToken is IERC20Metadata, Ownable {
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;

    string private _name;
    string private _symbol;
    uint256 private _totalSupply;

    uint256 public cashbackPercentage;
    uint256 public cashbackInterval;
    uint256 public taxPercentage;
    uint8 public activate;
    uint256 private averageGasPrice;

    uint256 public distributionRewardPool;
    uint256 private _liquidityRewardPool;

    address public AmusedVault;
    address public admin;


    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping(address => bool) public excluded;
    mapping(address => Cashback) public cashbacks;
    mapping(address => address) public referrers;

    struct Cashback {
        address user;
        uint256 totalClaimedCashback;
        uint256 timestamp;
    }

    event LiquidityInjected(uint amountToken, uint amountETH, uint liquidity, uint256 timestamp);
    event CashBack(address user, uint256 amount, uint256 timestamp);
    event Referral(address indexed user, address indexed referrer, uint256 timestamp);
    event ReferralReward(address indexed user, address indexed referrer, uint256 purchased, uint256 reward, uint256 timestamp);
    event GasRefund(address indexed user, uint256 amount, uint256 timestamp);
    event AmuseVault(address indexed vault, uint256 timestamp);
    event AmuseVaultMint(address indexed vault, uint256 amount, uint256 timestamp);

    constructor() {
        _name = "Amuse.Finance";
        _symbol = "AMD";

        taxPercentage = 10;
        cashbackPercentage = 2;
        cashbackInterval = 24 hours;
        averageGasPrice = 7 gwei;

        uint256 _initalSupply = 15000000 ether;
        uint256 _deployerAmount = (_initalSupply * 70) / 100;

        _mint(_msgSender(), _deployerAmount);
        _mint(address(this),  _initalSupply - _deployerAmount);
        distributionRewardPool =  _initalSupply - _deployerAmount;

        cashbacks[_msgSender()] = Cashback(_msgSender(), 0, block.timestamp);

        /* 
            instantiate uniswapV2Router & uniswapV2Factory
            uniswapV2Router address: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
            pancakeswapV2Router address: 0xD99D1c33F9fC3444f8101754aBC46c52416550D1
        */
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Factory = IUniswapV2Factory(uniswapV2Router.factory());

        // create AMD -> WETH pair
        uniswapV2Factory.createPair(address(this), uniswapV2Router.WETH());

        excluded[address(this)] = true;
        excluded[address(uniswapV2Router)] = true;
    }

    receive() external payable {  }


    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        uint256 _initalBalance = _balances[account];
        uint256 _cashback = calculateCashback(account);
        uint256 _finalBalance = _initalBalance + _cashback;
        return _finalBalance;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        uint256 _referrerRewards = _calculateReferrerRewards(amount);
        _transferReferrerFee(_msgSender(), recipient, amount, _referrerRewards);

        /*
            Note:: Gas refunds is only applicable to all AMD buy actions from users
        */
        _refundGas(recipient);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        (uint256 _finalAmount, uint256 _taxAmount) = _beforeTokenTransfer(sender, recipient, amount);

        // settle eligible cashback earned
        _claimCashback(sender);
        _claimCashback(recipient);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
    
        _balances[sender] = senderBalance - amount;
        _balances[address(this)] += _taxAmount;
        _balances[recipient] += _finalAmount;

        // collect tax and distribute based on the algorithm in "_distibuteTax" function
        _distibuteTax(_taxAmount);

        // Set Initial Cashback state when a new user purchases AMD token
        if(_balances[sender] > 0 && cashbacks[sender].timestamp == 0) 
            cashbacks[sender] = Cashback(sender, 0, block.timestamp);

        if(_balances[recipient] > 0 && cashbacks[recipient].timestamp == 0) 
            cashbacks[recipient] = Cashback(recipient, 0, block.timestamp);

        // reset lastClaimedCashback if balance <= 0
        _resetLastClaimedTime(sender);
        _resetLastClaimedTime(recipient);

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function burn(uint256 _amount) external {
        _burn(_msgSender(), _amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(address, address to, uint256 amount) internal virtual returns(uint256 _finalAmount, uint256 _taxAmount) { 
        if(taxPercentage == 0 || excluded[_msgSender()] || to == AmusedVault) return(amount, 0);

        // calculate transaction fees
        _taxAmount = (amount * taxPercentage) / 100;
        _finalAmount = amount - _taxAmount;
        return(_finalAmount, _taxAmount);
    }

    // Untracked
    function _distibuteTax(uint256 _tax) internal returns(uint8) {
        if(_tax == 0) return 0;
        uint256 _splitedTax = _tax / 4;

        // 50% of the collected tax is injected into liquidity
        _liquidityRewardPool += (_splitedTax * 2);
        _injectLiquidity();
        // 25% of the collected tax is burnt from the totalsupply
        _burn(address(this), _splitedTax);
        // the remaining 25% tax is issued to the refferer of the current buyer else it is added into the "distributionRewardPool"
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

    function setTaxPercentage(uint256 _amount) external onlyOwner {
        taxPercentage = _amount;
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

    // Start Cashback Logics
    function calculateDailyCashback(address _recipient) public view returns(uint256) {
        if(_balances[_recipient] == 0) return 0;
        uint256 _balance = _balances[_recipient];
        uint256 _rewards = (_balance * cashbackPercentage) / 100;
        return _rewards;
    }

    function calculateCashback(address _recipient) public view returns(uint256 _rewards) {
        if(
            _balances[_recipient] == 0 || 
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
        if(distributionRewardPool < _rewards) {
            uint256 _diff = _rewards - distributionRewardPool;
            _mint(address(this), _diff);
            distributionRewardPool += _diff;
        }
        distributionRewardPool -= _rewards;
        _transfer(address(this), _recipient, _rewards);
    }

    function _resetLastClaimedTime(address _account) private returns(uint8) {
        if(_balances[_account] > 0) return 0;
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
        distributionRewardPool += _rewards;
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

    function _injectLiquidity() internal returns(uint8) {
        if(_msgSender() == getPair() || activate == 0 || _liquidityRewardPool == 0 || excluded[_msgSender()]) return 0;

        // Note:: Liquidity will not be automatically injected because UniswapV2 doesn't fully tokens with transfer fee.
        // So a more elegant approach is to maintain the liquidity rewards in the contract and inject LP automatically during normal transfer in the contract
        // The approach will reduced gas fee significantly

        address[] memory path = new address[](2);
        uint256[] memory amounts;

        uint256 _splitAmount = _liquidityRewardPool / 2;

        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        amounts = getAmountsOut(address(this), uniswapV2Router.WETH(), _splitAmount);

        // approve tokens to be spent
        _approve(address(this), address(uniswapV2Router), _liquidityRewardPool);
        // swap token for ETH
        uniswapV2Router.swapExactTokensForETH(_splitAmount, 0, path, address(this), block.timestamp);
        // add Liquidity
        (uint _amountToken, uint _amountETH, uint _liquidity) = uniswapV2Router.addLiquidityETH{ value: amounts[1] }(
            address(this),
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
}