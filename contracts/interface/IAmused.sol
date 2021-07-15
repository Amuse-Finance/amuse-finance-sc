// SPDX-License-Identifier: MIT 
pragma solidity 0.8.5;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface IAmused is IERC20 {
    function taxPercentage() external returns(uint256);
    function amuseVaultMint(uint256 _amount) external;
    function fundRewardsPool(uint256 _amount) external;
}