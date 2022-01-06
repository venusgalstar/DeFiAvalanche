// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FireNFT is ERC721, Ownable {
    address private TreasuryWallet;
    address private RewardWallet;
    address private MaintenanceWallet;

    enum NFT_TYPE{ 
        MASTER_NFT, 
        GRAND_NFT
    }
   
    event SetMasterNFTPrice(address addr, uint256 newNFTPrice);
    event SetGrandNFTPrice(address addr, uint256 newNFTPrice);
    event SetBaseURI(address addr, string newUri);
    event SetMasterNFTURI(address addr, string newUri);
    event SetGrandNFTURI(address addr, string newUri);
    event SetRewardWalletAddress(address addr, address rewardWallet);

    using Strings for uint256;

    address constant _multisignWallet               	= 0x697A32dB1BDEF9152F445b06d6A9Fd6E90c02E3e;
    // address constant _multisignWallet               	= 0x13Bf16A02cF15Cb9059AC93c06bAA58cdB9B2a59;

    uint256 private constant MAX_MASTER_NFT_SUPPLY          = 100000;
    uint256 private constant MAX_MASTER_NFT_SUPPLY_PER_USER = 10;
    uint256 private MASTER_NFT_PRICE                        = 10;    //FIRE token

    uint256 private constant MAX_GRAND_NFT_SUPPLY           = 10000;
    uint256 private constant MAX_GRAND_NFT_SUPPLY_PER_USER  = 1;
    uint256 private GRAND_NFT_PRICE                         = 100;//FIRE token

    using Counters for Counters.Counter;
    Counters.Counter private _masterTokenCounter;
    Counters.Counter private _grandTokenCounter;
    
    string private _baseURIExtended;

    string private masterNFTURI;
    string private grandNFTURI;

    /**
    * @dev Throws if called by any account other than the multi-signer.
    */
    modifier onlyMultiSignWallet() {
        require(_multisignWallet == _msgSender(), "Multi-signer: caller is not the multi-signer");
        _;
    }
    
    constructor() ERC721("FIRE NFT","FNFT") {
        _baseURIExtended = "https://ipfs.infura.io/";
    }

    function setRewardWalletAddress(address _newRewardWallet) external onlyMultiSignWallet{
        RewardWallet = _newRewardWallet;
        emit SetRewardWalletAddress(msg.sender, _newRewardWallet);
    }

    //Set, Get Price Func

    function setMasterNFTPrice(uint256 _newNFTValue) external onlyMultiSignWallet{
        MASTER_NFT_PRICE = _newNFTValue;
        emit SetMasterNFTPrice(msg.sender, _newNFTValue);
    }

    function getMasterNFTPrice() external view returns(uint256){
        return MASTER_NFT_PRICE;
    }

    function setGrandNFTPrice(uint256 _newNFTValue) external onlyMultiSignWallet{
        GRAND_NFT_PRICE = _newNFTValue;
        emit SetGrandNFTPrice(msg.sender, _newNFTValue);
    }

    function getGrandNFTPrice() external view returns(uint256){
        return GRAND_NFT_PRICE;
    }

    function getMasterNFTURI() external view returns(string memory){
        return masterNFTURI;
    }

    function setMasterNFTURI(string memory _masterNFTURI) external onlyMultiSignWallet{
        masterNFTURI = _masterNFTURI;
        emit SetMasterNFTURI(msg.sender, _masterNFTURI);
    }

    function getGrandNFTURI() external view returns(string memory){
        return grandNFTURI;
    }

    function setGrandNFTURI(string memory _grandNFTURI) external onlyMultiSignWallet{
        grandNFTURI = _grandNFTURI;
        emit SetGrandNFTURI(msg.sender, _grandNFTURI);
    }

   /**
    * @dev Mint NFT by customer
    */
    function mintNFT(address sender, uint256 _nftType) external{

        require( msg.sender == RewardWallet, "you can't mint from other account");

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
        require(_masterTokenCounter.current() < MAX_MASTER_NFT_SUPPLY, "Total Master NFT Minting has already ended");
        require(balanceOf(sender) < MAX_MASTER_NFT_SUPPLY_PER_USER, "User Master NFT Minting has already ended");

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
        require(_grandTokenCounter.current() < MAX_GRAND_NFT_SUPPLY, "Total GRAND NFT Minting has already ended");
        require(balanceOf(sender) == MAX_MASTER_NFT_SUPPLY_PER_USER, "User Master NFT Minting hasn't finished");
        require(balanceOf(sender) < MAX_MASTER_NFT_SUPPLY_PER_USER + MAX_GRAND_NFT_SUPPLY_PER_USER, "User Grand NFT Minting has already ended");

        // Incrementing ID to create new token        
        uint256 newGrandNFTID = _grandTokenCounter.current() + MAX_MASTER_NFT_SUPPLY;
        _grandTokenCounter.increment();

        _safeMint(sender, newGrandNFTID);   
        return newGrandNFTID;     
    }

    /**
     * @dev Return the base URI
     */
     function _baseURI() internal override view returns (string memory) {
        return _baseURIExtended;
    }

    /**
     * @dev Set the base URI
     */
    function setBaseURI(string memory baseURI_) external onlyMultiSignWallet() {
        _baseURIExtended = baseURI_;
        emit SetBaseURI(msg.sender, baseURI_);
    }
}