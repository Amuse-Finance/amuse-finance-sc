// SPDX-License-Identifier: MIT 
pragma solidity 0.8.5;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface IAmused is IERC20 {
    function taxPercentage() external returns(uint256);
    function amuseVaultRewards(uint256 _amount) external;
    function sync() external;
    function rewardsPool() external returns(uint256);
    function  WETH() external returns(address WETH);
}