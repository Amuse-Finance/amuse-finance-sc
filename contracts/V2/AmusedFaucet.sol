// SPDX-License-Identifier: MIT 
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AmuseFaucet is Ownable {
    IERC20 public AmusedToken;
    uint256 public totalLockedAmount;
    uint256 public faucetInterval;
    
    mapping(address => uint256) public lastWithdrawTime;
    
    event Deposit(address user, uint256 amount, uint256 timestamp);
    event Faucet(address account, uint256  amount, uint256 timestamp);
    
    constructor(IERC20 _amusedToken) {
        AmusedToken = _amusedToken;
        faucetInterval = 24 hours;
    }
    
    receive() external payable {
        revert();
    }
    
    function requestFaucet(address _account, uint256 _amount) external {
        require(isValidWithdrawal(_account));
        
        lastWithdrawTime[_account] = block.timestamp;
        totalLockedAmount -= _amount;
        AmusedToken.transfer(_account, _amount);
        emit Faucet(_account, _amount, block.timestamp);
    }
    
    function isValidWithdrawal(address _account) public view returns(bool) {
        require(block.timestamp > lastWithdrawTime[_account] + faucetInterval, "AmuseFaucet: Faucet has already been issued to address");
        return true;
    }
    
    function withdrawToken(uint256 _amount) external onlyOwner {
        totalLockedAmount -= _amount;
        AmusedToken.transfer(_msgSender(), _amount);
    }
    
    function sync() external {
        uint256 _balance = AmusedToken.balanceOf(address(this));
        if(_balance > totalLockedAmount) totalLockedAmount += (_balance - totalLockedAmount);
    }
    
    function setFaucetInterval(uint256 _interval) external onlyOwner {
        faucetInterval = _interval;
    }
}