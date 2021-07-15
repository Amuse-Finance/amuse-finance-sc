// SPDX-License-Identifier: MIT
pragma solidity 0.8.5;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract AmuseExchange is Initializable {
    IERC20Upgradeable public AmuseToken;

    function initialize(IERC20Upgradeable _amuseToken) public initializer {
        AmuseToken = _amuseToken;
    }

}