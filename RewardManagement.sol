// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./FireToken.sol";
import "./FireNFT.sol";
import "./IJoeRouter02.sol";

contract RewardManagement is Ownable{
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    uint256 pauseContract;

    enum NFT_TYPE{
        MASTER_NFT,
        GRAND_NFT
    }

    enum MODE_FEE{
        THREE_MONTH,
        SIX_MONTH
    }
    
    struct NodeInfo {
        uint256 createTime;
        uint256 lastTime;
        uint256 reward;
    }

    struct ImportNodeInfo {
        address buyer;
        uint256 createTime;
    }
 
    struct ImportNftInfo {
        address addr;
        uint256 typeOfNFT;
        uint256 createTime;
    }
 
    struct NFTInfo {
        uint256     createTime;
        NFT_TYPE    typeOfNFT;
    }

    struct RewardInfo {
        uint256 currentTime;
        uint256 lastClaimTime;
        uint256[] nodeRewards;
        bool[] enableNode;
        bool[] curMasterNFTEnable;
        bool[] curGrandNFTEnable;
    }

    event Received(address, uint);
    event Fallback(address, uint);
    event PurchasedNode(address buyer, uint256 amount);
    event PurchasedNFT(address addr, uint256 typeOfNFT, uint256 nftCount);
    event PayNodeFee(address addr, uint256 nodeId, uint256 feeMode);
    event PayAllNodeFee(address addr, uint256 feeMode);

    event DeleteUserNode(address addr);
    event ClaimNode(address addr, uint256 nodeId, uint256 reward);
    event ClaimAllNode(address addr, uint256 reward);
    event WithdrawAll(address addr, uint256 fire, uint256 avax);
    event SetContractStatus(address addr, uint256 _newPauseContract);
    event SetNodeMaintenanceFee(address addr, uint256 newThreeMonthFee);
    event SetNFTContract(address addr);
    event ClearUserInfo(address addr);
    event ImportNode(address addr, uint256 nodeCount);
    event ImportNFT(address addr, uint256 nftCount);
    event SetNodePrice(address addr, uint256 newNodePrice);
    event SetFireValue(address addr, uint256 newFireValue);
    event SetClaimFee(address addr, uint256 newClaimFee); 

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 avaxReceived,
        uint256 tokensIntoLiqudity
    );
  
    IJoeRouter02        public _joe02Router;

    address constant _multisignWallet               = 0x697A32dB1BDEF9152F445b06d6A9Fd6E90c02E3e;
    // address constant _multisignWallet               = 0x13Bf16A02cF15Cb9059AC93c06bAA58cdB9B2a59;
    address payable constant _treasuryWallet        = payable(0x52Fd04AA057ba8Ca4bCc675B55De7366F607A677);
    address payable constant _maintenanceWallet     = payable(0xcdd337ac33bE88D437CfAe5E1538ee73C8c76f98);
    address public  constant _burnAddress           = 0x000000000000000000000000000000000000dEaD;

    uint256 constant _rewardRateForTreasury         = 2;
    uint256 constant _rewardRateForStake            = 7;
    uint256 constant _rewardRateForLiquidity        = 1;
    uint256 constant REWARD_NODE_PER_SECOND         = 225 * 10**15 / (uint256)(3600 * 24);  // 0.225
    uint256 constant REWARD_MASTER_NFT_PER_SECOND   = 25 * 10**15 / (uint256)(3600 * 24);   // 0.025
    uint256 constant REWARD_GRAND_NFT_PER_SECOND    = 50 * 10**15 / (uint256)(3600 * 24);   // 0.05
    uint256 NODE_PRICE                              = 10 * 10**18;                          // 10 FIRE
    uint256 constant NODECOUNT_PER_MASTERNFT        = 10;                                   // 10 NODE
    uint256 constant NODECOUNT_PER_GRANDNFT         = 100;                                  // 100 NODE
    uint256 constant MAX_NODE_PER_USER              = 100;                                  // 100 NODE
    uint256 constant ONE_MONTH_TIME                 = 2592000;                              // seconds for one month
    uint256 constant ONE_DAY_TIME                   = 86400;                                // seconds for one day
    uint256 THREE_MONTH_PRICE                       = 20 * 10**16;                          // 20 AVAX
    uint256 CLAIM_FEE                               = 5 * 10**16;                           // 5 AVAX
    uint256 FIRE_VALUE                              = 1 * 10**18;                           // 10 AVAX 
    uint256 constant MAX_MASTER_NFT_COUNT           = 10;                                   // maximum master nft count
    uint256 constant MAX_REWARD_PER_CLAIM           = 100 * 10**18;                         // maximum fire count per claim
    FireToken public _tokenContract;
    FireNFT public _nftContract;
    
    IERC20 private _usdcToken;

    uint256 public totalNodeCount;
    mapping(address => uint256) private _rewardsOfUser;
    mapping(address => uint256) private _lastClaimOfUser;
    mapping(address => NodeInfo[]) private _nodesOfUser;
    mapping(address => NFTInfo[]) private _nftOfUser;
    
    /**
    * @dev Throws if called by any account other than the multi-signer.
    */
    modifier onlyMultiSignWallet() {
        require(owner() == _msgSender(), "Multi-signer: caller is not the multi-signer");
        _;
    }

    constructor(address tokenContract, address nftContract) { 
        _tokenContract = FireToken(tokenContract);
        _nftContract = FireNFT(nftContract);
        _joe02Router = IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        _usdcToken = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);
        pauseContract = 0;
        totalNodeCount = 0;
    }
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    fallback() external payable { 
        emit Fallback(msg.sender, msg.value);
    }

    function setNFTContract(address addr) external onlyMultiSignWallet {
        _nftContract = FireNFT(addr);
        emit SetNFTContract(addr);
    }

    function clearUserInfo(address addr) external onlyMultiSignWallet {
        totalNodeCount -= _nodesOfUser[addr].length;
        delete _nodesOfUser[addr];
        delete _nftOfUser[addr];
        emit ClearUserInfo(addr);
    }
    
    function importNodeInfo(ImportNodeInfo[] memory nodeInfos) external onlyMultiSignWallet{
        uint256 i;
        for(i=0; i<nodeInfos.length; i++) {
            _nodesOfUser[nodeInfos[i].buyer].push(
                NodeInfo({ createTime: nodeInfos[i].createTime, lastTime:nodeInfos[i].createTime + ONE_MONTH_TIME * 3, reward:0})
            );
            totalNodeCount++;
        }
        require(i==nodeInfos.length, "not complete transaction");
        emit ImportNode(msg.sender, nodeInfos.length);
    }

    function importNftInfo(ImportNftInfo[] memory nftInfos, bool bNewMint) external onlyMultiSignWallet {
        uint256 i;
        for(i=0; i<nftInfos.length; i++) {
            _nftOfUser[nftInfos[i].addr].push(
                NFTInfo({ createTime: nftInfos[i].createTime, typeOfNFT: NFT_TYPE(nftInfos[i].typeOfNFT)})
            );
            if(bNewMint == true) {
                _nftContract.mintNFT(nftInfos[i].addr, nftInfos[i].typeOfNFT);     
            }
        }
        require(i==nftInfos.length, "not complete transaction");
        emit ImportNFT(msg.sender, nftInfos.length);
    }

    function withdrawAll() external onlyMultiSignWallet{
        uint256 balance = _tokenContract.balanceOf(address(this));
        if(balance > 0) {
            _tokenContract.transfer(msg.sender, balance);
        }
        
        address payable mine = payable(msg.sender);
        if(address(this).balance > 0) {
            mine.transfer(address(this).balance);
        }
        emit WithdrawAll(msg.sender, balance, address(this).balance);
    }

    function setNodePrice(uint256 _newNodePrice) external onlyMultiSignWallet () {
        NODE_PRICE = _newNodePrice;
        emit SetNodePrice(msg.sender, _newNodePrice);
    }

    function getNodePrice() external view returns (uint256) {
        return NODE_PRICE;
    }

    function setFireValue(uint256 _newFireValue) external onlyMultiSignWallet(){
        FIRE_VALUE = _newFireValue;
        emit SetFireValue(msg.sender, _newFireValue);
    }

    function getFireValue() external  view returns(uint256){
        return FIRE_VALUE;
    }

    function getMasterNFTPrice() external view returns (uint256) {
        return FIRE_VALUE * NODECOUNT_PER_MASTERNFT;
    }

    function getGrandNFTPrice() external view returns (uint256) {
        return FIRE_VALUE * NODECOUNT_PER_GRANDNFT;
    }

    function setClaimFee(uint256 _newClaimFee) external onlyMultiSignWallet () {
        CLAIM_FEE = _newClaimFee;
        emit SetClaimFee(msg.sender, _newClaimFee); 
    }

    function getClaimFee() external view returns (uint256) {
        return CLAIM_FEE;        
    }

    function getContractStatus() external view returns (uint256) {
        return pauseContract;
    }

    function setContractStatus(uint256 _newPauseContract) external onlyMultiSignWallet {
        pauseContract = _newPauseContract;
        emit SetContractStatus(msg.sender, _newPauseContract);
    }

    function getNodeMaintenanceFee() external view returns (uint256) {
        return THREE_MONTH_PRICE;
    }

    function setNodeMaintenanceFee(uint256 _newThreeMonthFee) external onlyMultiSignWallet {
        THREE_MONTH_PRICE = _newThreeMonthFee;
	emit SetNodeMaintenanceFee(msg.sender, _newThreeMonthFee);
    }
    
    function getTotalNodeCount() external view returns(uint256) {
        return totalNodeCount;
    }
    
    function getNodeList(address addr) view external returns(NodeInfo[] memory result){
        result = _nodesOfUser[addr];
        return result;
    }

    function getNFTList(address addr) view external returns(NFTInfo[] memory result){
        result = _nftOfUser[addr];
        return result;
    }

    function getAvaxForUSD(uint usdAmount) public view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = address(_usdcToken);
        path[1] = _joe02Router.WAVAX();
        return _joe02Router.getAmountsOut(usdAmount, path)[1];
    }

    function getAvaxForFire(uint fireAmount) public view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = address(_tokenContract);
        path[1] = _joe02Router.WAVAX();
        return _joe02Router.getAmountsOut(fireAmount, path)[1];
    }

    function getTreasuryAmount() external view returns(uint){
        return address(_treasuryWallet).balance;
    }

    function getTreasuryRate() external view returns(uint){
        uint256 total_balance = address(_treasuryWallet).balance;
        return total_balance.div(_tokenContract.balanceOf(address(this)));
    }
    
    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);
        uint256 initialBalance = address(this).balance;

        swapTokensForAVAX(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForAVAX(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(_tokenContract);
        path[1] = _joe02Router.WAVAX();

        _tokenContract.approve(address(_joe02Router), tokenAmount);
                    
        _joe02Router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of WAVAX
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 avaxAmount) private {
        // approve token transfer to cover all possible scenarios
        _tokenContract.approve(address(_joe02Router), tokenAmount);

        // add the liquidity
        _joe02Router.addLiquidityAVAX{value: avaxAmount}(
            address(_tokenContract),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(_burnAddress),
            block.timestamp
        );
    }

    function buyNode(uint256 numberOfNodes) external payable{
        require(pauseContract == 0, "Contract Paused");
        uint256 numberOfTokens = numberOfNodes * NODE_PRICE;
        uint256 prevNumberOfNode = _nodesOfUser[msg.sender].length;
        
        require(_tokenContract.balanceOf(msg.sender) >= numberOfTokens, "user doesn't have enough token balance");
        require(prevNumberOfNode + numberOfNodes <= MAX_NODE_PER_USER, "can't buy more than 100 nodes");
        
        // send 8 Fire to RewardPool: 7 Fire for rewardPool, 1 Fire for liquidity
        uint256 numberOfStaking;
        numberOfStaking = numberOfTokens * _rewardRateForStake/10;
        numberOfStaking += numberOfTokens * _rewardRateForLiquidity/10;

        _tokenContract.transferFrom(msg.sender, address(this), numberOfStaking);        

        // send 2 Fire _treasuryWallet
        _tokenContract.transferFrom(msg.sender, _treasuryWallet, numberOfTokens * _rewardRateForTreasury / 10);

        // send 1 Fire to liquidity        
        swapAndLiquify(numberOfTokens * _rewardRateForLiquidity / 10);
        
        // make node for buyer
        for(uint256 i=0; i<numberOfNodes; i++) {
            _nodesOfUser[msg.sender].push(
                NodeInfo({ createTime: block.timestamp, lastTime:block.timestamp + ONE_MONTH_TIME * 3, reward:0})
            );
        }

        // pay 3 months fee
        require(msg.value == THREE_MONTH_PRICE, "no enough balance");
        _maintenanceWallet.transfer(msg.value);

        totalNodeCount += numberOfNodes;
        
        // emit purchased node event
        emit PurchasedNode(msg.sender, numberOfNodes);
    }

    function buyNFT(NFT_TYPE typeOfNFT, uint nftCount) external payable{
        require(pauseContract == 0, "Contract Paused");

        address addr = msg.sender;
        uint avNodeCount = _nodesOfUser[addr].length;
        uint prevNFTCount = _nftOfUser[addr].length;
        uint prevMasterNFTCount = prevNFTCount == MAX_MASTER_NFT_COUNT+1 ? MAX_MASTER_NFT_COUNT : prevNFTCount;
        uint prevGrandNFTCount = prevNFTCount == MAX_MASTER_NFT_COUNT+1 ? 1 : 0;
        uint remainNodeCount = avNodeCount - prevMasterNFTCount * NODECOUNT_PER_MASTERNFT;
        uint256 nftPrice;
        if(typeOfNFT == NFT_TYPE.GRAND_NFT) {
            require(prevGrandNFTCount == 0, "have already grand nft");
            require(nftCount == 1, "buy only 1 grand nft");
            require(prevMasterNFTCount == MAX_MASTER_NFT_COUNT, "no need grand nft for now");
            nftPrice = NODECOUNT_PER_GRANDNFT * FIRE_VALUE;
        } else {
            require(avNodeCount >= prevMasterNFTCount * NODECOUNT_PER_MASTERNFT, "no need so many master");
            require(remainNodeCount / NODECOUNT_PER_MASTERNFT >= nftCount, "no need so many master nft");
            require(prevMasterNFTCount + nftCount <=MAX_MASTER_NFT_COUNT, "no need more than 10 master nft");
            nftPrice = NODECOUNT_PER_MASTERNFT * FIRE_VALUE;
        }
        // payment with avax
        require(msg.value == nftPrice, "no enough AVAX");
        _maintenanceWallet.transfer(msg.value);     

        for(uint i=0; i<nftCount; i++) {
            _nftContract.mintNFT(msg.sender, uint256(typeOfNFT));
            _nftOfUser[addr].push(NFTInfo({createTime: block.timestamp, typeOfNFT : typeOfNFT}));
        }
        
        emit PurchasedNFT(msg.sender, uint256(typeOfNFT), nftCount);
    }

    function payAllNodeFee(MODE_FEE feeMode) public payable {
        require(pauseContract == 0, "Contract Paused");

        uint256 payVal;
        uint256 nodeLength = _nodesOfUser[msg.sender].length;
        uint256 payCount;
        address payable addr = payable(msg.sender);

        if(feeMode == MODE_FEE.THREE_MONTH) {
            payVal = THREE_MONTH_PRICE;
        } else if(feeMode == MODE_FEE.SIX_MONTH) {
            payVal = THREE_MONTH_PRICE * 2;
        }

        payCount = 0;

        for(uint i=0; i<nodeLength; i++){
            if(block.timestamp + ONE_MONTH_TIME < _nodesOfUser[msg.sender][i].lastTime) 
                continue;
	    
            if(block.timestamp > _nodesOfUser[msg.sender][i].lastTime) {
                _nodesOfUser[msg.sender][i].createTime = block.timestamp;
                _nodesOfUser[msg.sender][i].lastTime = block.timestamp;
                _nodesOfUser[msg.sender][i].reward = 0;
            }
            if(feeMode == MODE_FEE.THREE_MONTH) {
                _nodesOfUser[msg.sender][i].lastTime += 3 * ONE_MONTH_TIME;
            } else if(feeMode == MODE_FEE.SIX_MONTH) {
                _nodesOfUser[msg.sender][i].lastTime += 6 * ONE_MONTH_TIME;
            }
            payCount++;
        }
        require(msg.value >= payVal * payCount, "no enough balance");
        _maintenanceWallet.transfer(payVal * payCount);
        addr.transfer(msg.value - payVal * payCount);

        emit PayAllNodeFee(msg.sender, uint256(feeMode));
    }

    function payNodeFee(uint256 nodeId, MODE_FEE feeMode) external payable{
        require(pauseContract == 0, "Contract Paused");

        address payable addr = payable(msg.sender);
        require(block.timestamp + ONE_MONTH_TIME> _nodesOfUser[addr][nodeId].lastTime, "already purchased");
        if(block.timestamp > _nodesOfUser[addr][nodeId].lastTime) {
            _nodesOfUser[addr][nodeId].createTime = block.timestamp;
            _nodesOfUser[addr][nodeId].lastTime = block.timestamp;
            _nodesOfUser[addr][nodeId].reward = 0;
        }
        if(feeMode == MODE_FEE.THREE_MONTH) {
            require(msg.value == THREE_MONTH_PRICE, "no enough balance");
            _nodesOfUser[addr][nodeId].lastTime += 3 * ONE_MONTH_TIME;
        } else if(feeMode == MODE_FEE.SIX_MONTH) {
            require(msg.value == THREE_MONTH_PRICE * 2, "no enough balance");
            _nodesOfUser[addr][nodeId].lastTime += 6 * ONE_MONTH_TIME;
        }
        _maintenanceWallet.transfer(msg.value);

        emit PayNodeFee(msg.sender, nodeId, uint256(feeMode));
    }

    function claimByNode(uint256 nodeId) external payable{
        require(pauseContract == 0, "Contract Paused");
        require(_nodesOfUser[msg.sender].length > nodeId, "invalid Node ID");
        require(msg.value == CLAIM_FEE, "no enough balance");
        require(block.timestamp > _lastClaimOfUser[msg.sender] + ONE_DAY_TIME, "should claim once within 1 day");
        
        require(_nodesOfUser[msg.sender][nodeId].lastTime > block.timestamp, "expired node claim"); 

        // add rewards and initialize timestamp for all enabled nodes     
        uint256 nodeReward = getRewardAmountByNode(msg.sender, nodeId);
        _nodesOfUser[msg.sender][nodeId].createTime = block.timestamp;
        
        // send FireToken rewards of nodeId to msg.sender
        require(nodeReward > 0, "There is no rewards.");
        require(_tokenContract.balanceOf(address(this)) > nodeReward, "no enough balance on phoenix");
        if(nodeReward > MAX_REWARD_PER_CLAIM) {
            _nodesOfUser[msg.sender][nodeId].reward = nodeReward - MAX_REWARD_PER_CLAIM;
            nodeReward = MAX_REWARD_PER_CLAIM;
        }
        _tokenContract.transfer(msg.sender, nodeReward);
        
        // set last claim time
        _lastClaimOfUser[msg.sender] = block.timestamp;
        
        // fee payment 5$ to do
        _maintenanceWallet.transfer(msg.value);
        emit ClaimNode(msg.sender, nodeId, nodeReward);
    }

    function claimAll() external payable{
        require(pauseContract == 0, "Contract Paused");
        require(block.timestamp > _lastClaimOfUser[msg.sender] + ONE_DAY_TIME, "should claim once within 1 day");

        uint256 nodeCount = _nodesOfUser[msg.sender].length;
        NFTInfo[] storage nfts = _nftOfUser[msg.sender];
        //calculate nft count
        uint256 masterNftCount;
        uint256 grandNftCount;
        if( nfts.length <= MAX_MASTER_NFT_COUNT ) {
            masterNftCount = nfts.length * NODECOUNT_PER_MASTERNFT;
            grandNftCount = 0;
        } else {
            masterNftCount = MAX_MASTER_NFT_COUNT * NODECOUNT_PER_MASTERNFT;
            grandNftCount =  NODECOUNT_PER_GRANDNFT;
        }
                
        uint256 rewards = 0;
        uint256 oneReward;
        uint256 nEnableCount = 0;
        uint256 duringTime;
        for(uint i=0; i<nodeCount; i++) {
            if(_nodesOfUser[msg.sender][i].lastTime >= block.timestamp) {
                oneReward = _nodesOfUser[msg.sender][i].reward;
                oneReward += (block.timestamp - _nodesOfUser[msg.sender][i].createTime) * REWARD_NODE_PER_SECOND;
                if(nEnableCount < masterNftCount) {
                    duringTime = block.timestamp - Math.max(_nodesOfUser[msg.sender][i].createTime, nfts[nEnableCount / NODECOUNT_PER_MASTERNFT].createTime);
                    oneReward += duringTime * REWARD_MASTER_NFT_PER_SECOND;
                }
                if(nEnableCount < grandNftCount) {
                    duringTime = block.timestamp - Math.max(_nodesOfUser[msg.sender][i].createTime, nfts[nEnableCount / NODECOUNT_PER_GRANDNFT].createTime);
                    oneReward += duringTime * REWARD_GRAND_NFT_PER_SECOND;
                }
                
                _nodesOfUser[msg.sender][i].createTime = block.timestamp;
                _nodesOfUser[msg.sender][i].reward = 0;
                nEnableCount++;
                if(rewards + oneReward > MAX_REWARD_PER_CLAIM) {
                    _nodesOfUser[msg.sender][i].reward = rewards + oneReward - MAX_REWARD_PER_CLAIM;
                    rewards = MAX_REWARD_PER_CLAIM;
                    break;
                }
                rewards += oneReward;
            }
        }

        // fee payment 5$ to do
        require(msg.value >= CLAIM_FEE * nEnableCount, "no enough balance for claim fee");
        _maintenanceWallet.transfer(msg.value);

        // send FireToken rewards to msg.sender
        require(rewards > 0, "There is no rewards.");
        require(_tokenContract.balanceOf(address(this)) > rewards, "no enough balance on phoenix");
        _tokenContract.transfer(msg.sender, rewards);

        // set last claim time
        _lastClaimOfUser[msg.sender] = block.timestamp;
        emit ClaimAllNode(msg.sender, rewards);
    }


    function getRewardAmountByNode(address addr, uint256 nodeId) view private returns(uint256){

        uint256 nftLength = _nftOfUser[addr].length;
        uint256 nodeCreatTime = _nodesOfUser[addr][nodeId].createTime;
        uint256 nodeLength = _nodesOfUser[addr].length;

        uint256 rewardAmount;
        uint256 duringTime;

        //calculate nft count
        uint256 masterNftCount = nftLength <= MAX_MASTER_NFT_COUNT ? nftLength : MAX_MASTER_NFT_COUNT;
        uint256 grandNftCount = nftLength <= MAX_MASTER_NFT_COUNT ? 0 : 1;

        //node count for nft applying
        uint256 enableMasterNftCount = Math.min(masterNftCount, nodeLength / NODECOUNT_PER_MASTERNFT);
        uint256 enableGrandNftCount = Math.min(grandNftCount, nodeLength / NODECOUNT_PER_GRANDNFT);

        duringTime = block.timestamp - nodeCreatTime;
        rewardAmount = _nodesOfUser[addr][nodeId].reward + duringTime * REWARD_NODE_PER_SECOND;

        //calculate master nft rewards per nodes
        if(nodeId < enableMasterNftCount * NODECOUNT_PER_MASTERNFT) {
            duringTime = block.timestamp - Math.max(nodeCreatTime, _nftOfUser[addr][nodeId / NODECOUNT_PER_MASTERNFT].createTime);
            rewardAmount += duringTime * REWARD_MASTER_NFT_PER_SECOND;
        }
        //calculate grand nft rewards per nodes
        if(nodeId < enableGrandNftCount * NODECOUNT_PER_GRANDNFT) {
            duringTime = block.timestamp - Math.max(nodeCreatTime, _nftOfUser[addr][nodeId / NODECOUNT_PER_GRANDNFT].createTime);
            rewardAmount += duringTime * REWARD_GRAND_NFT_PER_SECOND;
        }
        return rewardAmount;
    }

    function getRewardAmount(address addr) view external returns(RewardInfo memory){
        NFTInfo[] memory nfts = _nftOfUser[addr];
        NodeInfo[] memory nodes = _nodesOfUser[addr];

        RewardInfo memory rwInfo;
        rwInfo.currentTime = block.timestamp;
        rwInfo.lastClaimTime = _lastClaimOfUser[addr];
        rwInfo.nodeRewards = new uint256[](nodes.length);
        rwInfo.enableNode = new bool[](nodes.length);
        rwInfo.curMasterNFTEnable = new bool[](nodes.length);
        rwInfo.curGrandNFTEnable = new bool[](nodes.length);
        uint256 duringTime;

        //initialize node reward
        uint256 enableNodeCount = 0;
        uint256 i;
        for(i=0; i<nodes.length; i++) {
            rwInfo.curMasterNFTEnable[i] = false;
            rwInfo.curGrandNFTEnable[i] = false;
            rwInfo.nodeRewards[i] = nodes[i].reward;
            if( nodes[i].lastTime >= block.timestamp) {
                rwInfo.enableNode[i] = true;
                enableNodeCount++;
            } else {
                rwInfo.enableNode[i] = false;
            }
        }

        //calculate nft count
        uint256 masterNftCount;
        uint256 grandNftCount;
        masterNftCount = nfts.length <= MAX_MASTER_NFT_COUNT ? nfts.length : MAX_MASTER_NFT_COUNT;
        grandNftCount = nfts.length <= MAX_MASTER_NFT_COUNT ? 0 : 1;

        //node count for nft applying
        uint256 enableMasterNftCount = Math.min(masterNftCount, enableNodeCount / NODECOUNT_PER_MASTERNFT);
        uint256 enableGrandNftCount = Math.min(grandNftCount, enableNodeCount / NODECOUNT_PER_GRANDNFT);

        uint256 applyMasterNFT = 0;
        uint256 applyGrandNFT = 0;
        for(i=0; i<nodes.length; i++) {
            if( rwInfo.enableNode[i] == true ) {
                duringTime = block.timestamp - nodes[i].createTime;
                rwInfo.nodeRewards[i] += duringTime * REWARD_NODE_PER_SECOND;

                //calculate master nft rewards per nodes
                if(applyMasterNFT < enableMasterNftCount * NODECOUNT_PER_MASTERNFT) {
                    duringTime = block.timestamp - Math.max(nodes[i].createTime, nfts[applyMasterNFT / NODECOUNT_PER_MASTERNFT].createTime);
                    rwInfo.nodeRewards[i] += duringTime * REWARD_MASTER_NFT_PER_SECOND;
                    rwInfo.curMasterNFTEnable[i] = true;
                    applyMasterNFT++;
                }
                //calculate grand nft rewards per nodes
                if(applyGrandNFT < enableGrandNftCount * NODECOUNT_PER_GRANDNFT) {
                    duringTime = block.timestamp - Math.max(nodes[i].createTime, nfts[applyGrandNFT / NODECOUNT_PER_GRANDNFT].createTime);
                    rwInfo.nodeRewards[i] += duringTime * REWARD_GRAND_NFT_PER_SECOND;
                    rwInfo.curGrandNFTEnable[i] = true;
                    applyGrandNFT++;
                }
            }
        }
        return rwInfo;
    }
}