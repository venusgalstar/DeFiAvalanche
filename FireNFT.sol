// SPDX-License-Identifier: UNLICENSED
/**
 *Submitted for verification at Etherscan.io on 2021-12-06
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FireNFT is ERC721, Ownable {

    enum NFT_TYPE{ 
        MASTER_NFT, 
        GRAND_NFT
    }
   
    using Strings for uint256;
    using SafeMath for uint256;

    uint256 private MAX_MASTER_NFT_SUPPLY;
    uint256 private MAX_MASTER_NFT_SUPPLY_PER_USER;
    uint256 private MASTER_NFT_PRICE;    

    uint256 private MAX_GRAND_NFT_SUPPLY;
    uint256 private MAX_GRAND_NFT_SUPPLY_PER_USER;
    uint256 private GRAND_NFT_PRICE;

    using Counters for Counters.Counter;
    Counters.Counter private _masterTokenCounter;
    Counters.Counter private _grandTokenCounter;
    
    string private _baseURIExtended;

    string private masterNFTURI;
    string private grandNFTURI;

    constructor() ERC721("FIRE NFT","FNFT") {

        MAX_MASTER_NFT_SUPPLY = 100000;
        MAX_MASTER_NFT_SUPPLY_PER_USER = 10;
        MASTER_NFT_PRICE = 10;          //FIRE token

        MAX_GRAND_NFT_SUPPLY = 10000;
        MAX_GRAND_NFT_SUPPLY_PER_USER = 1;
        GRAND_NFT_PRICE = 100;          //FIRE token

        _baseURIExtended = "https://ipfs.infura.io/";
    }

    //Set, Get Price Func

    function setMasterNFTPrice(uint256 _newNFTValue) external onlyOwner{
        MASTER_NFT_PRICE = _newNFTValue;
    }

    function getMasterNFTPrice() external view returns(uint256){
        return MASTER_NFT_PRICE;
    }

    function setGrandNFTPrice(uint256 _newNFTValue) external onlyOwner{
        GRAND_NFT_PRICE = _newNFTValue;
    }

    function getGrandNFTPrice() external view returns(uint256){
        return GRAND_NFT_PRICE;
    }

    function getMasterNFTURI() external view returns(string memory){
        return masterNFTURI;
    }

    function setMasterNFTURI(string memory _masterNFTURI) external onlyOwner{
        masterNFTURI = _masterNFTURI;
    }

    function getGrandNFTURI() external view returns(string memory){
        return grandNFTURI;
    }

    function setGrandNFTURI(string memory _grandNFTURI) external onlyOwner{
        grandNFTURI = _grandNFTURI;
    }

   /**
    * @dev Mint NFT by customer
    */
    function mintNFT(address sender, uint256 _nftType) external{

        if( _nftType == uint256(NFT_TYPE.MASTER_NFT) )
        {
            _mintMasterNFT(sender);
        }
        else if( _nftType == uint256(NFT_TYPE.GRAND_NFT) )
        {
            _mintGrandNFT(sender);
        }
    }

   /**
    * @dev Mint masterNFT For Free
    */
    function _mintMasterNFT(address sender) internal returns(uint256){
        // Test _masterTokenCounter
        require(_masterTokenCounter.current() < MAX_MASTER_NFT_SUPPLY, "Master NFT Minting has already ended");
        require(balanceOf(sender) < MAX_MASTER_NFT_SUPPLY_PER_USER, "Master NFT Minting has already ended");

        // Incrementing ID to create new token        
        uint256 newMasterNFTID = _masterTokenCounter.current();
        _masterTokenCounter.increment();

        _safeMint(sender, newMasterNFTID);    
        return newMasterNFTID;
    }

    /**
    * @dev Mint grandNFT
    */
    function _mintGrandNFT(address sender) internal returns(uint256){
        // Test _grandTokenCounter
        require(_grandTokenCounter.current() < MAX_GRAND_NFT_SUPPLY, "GRAND NFT Minting has already ended");
        require(balanceOf(sender) == MAX_MASTER_NFT_SUPPLY_PER_USER, "Master NFT Minting has already ended");
        require(balanceOf(sender) < MAX_MASTER_NFT_SUPPLY_PER_USER + MAX_GRAND_NFT_SUPPLY_PER_USER, "Grand NFT Minting has already ended");

        // Incrementing ID to create new token        
        uint256 newGrandNFTID = _grandTokenCounter.current() + MAX_MASTER_NFT_SUPPLY;
        _grandTokenCounter.increment();

        _safeMint(sender, newGrandNFTID);   
        return newGrandNFTID;     
    }

    /**
     * @dev Return the base URI
     */
     function _baseURI() internal view returns (string memory) {
        return _baseURIExtended;
    }

    /**
     * @dev Set the base URI
     */
    function setBaseURI(string memory baseURI_) external onlyOwner() {
        _baseURIExtended = baseURI_;
    }
}