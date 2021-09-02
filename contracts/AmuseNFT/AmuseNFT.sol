// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

contract AmuseNFT is ERC721, ERC721URIStorage, ERC721Burnable, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter public tokenIdCounter;
    IERC20 public AmuseToken;
    uint256 public NFT_FEE;

    event Sold(address from, address recipient, uint256 tokenId, uint256 timestamp);
    event WithdrawFee(address from, address recipient, uint256 amount, uint256 timestamp);
    constructor(IERC20 _amuseToken) ERC721("Amuse Finance", "AMD") {
        AmuseToken = _amuseToken;
        NFT_FEE = 1000 ether;
    }

    receive() external payable { revert("AmuseNFT: ETHER transfer rejected"); }

    function mint(string memory _tokenURI) public onlyOwner {
        uint256  _tokenId = tokenIdCounter.current();
        _safeMint(address(this), _tokenId);
        tokenIdCounter.increment();
        _setTokenURI(_tokenId, _tokenURI);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function buy(uint256 _tokenId) external returns(uint8) {
        require(ownerOf(_tokenId) == address(this), "AmuseNFT: NFT has already been sold out");
        
        if(_msgSender() == owner()) {
            safeTransferFrom(address(this), _msgSender(), _tokenId);
            emit Sold(address(this), owner(), _tokenId, block.timestamp);
            return 0;
        }

        AmuseToken.transfer(address(this), NFT_FEE);
        safeTransferFrom(address(this), _msgSender(), _tokenId);
        emit Sold(address(this), _msgSender(), _tokenId, block.timestamp);
        return 1;
    }

    function withdrawFee(uint256 _amount) external onlyOwner {
        AmuseToken.transfer(_msgSender(), _amount);
        emit WithdrawFee(owner(), _msgSender(), _amount, block.timestamp);
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}