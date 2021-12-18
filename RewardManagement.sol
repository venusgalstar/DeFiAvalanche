//Contract based on https://docs.openzeppelin.com/contracts/3.x/erc721
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
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
 
    struct NFTInfo {
        uint256     createTime;
        NFT_TYPE    typeOfNFT;
    }

    struct RewardInfo {
        uint256 rewardBalance;
        uint256[] nodeRewards;
        bool[] enableNode;
        bool[] curMasterNFTEnable;
        bool[] curGrandNFTEnable;
    }

    event PurchasedNode(address buyer, uint256 amount);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 avaxReceived,
        uint256 tokensIntoLiqudity
    );
  
    IJoeRouter02        public _joe02Router;

    address payable constant _treasuryWallet        = 0xb812D0e88713BB4f510895Be4528C4B378A25dC2;
    address payable constant _maintenanceWallet     = 0xE8591918280D97f290712CE761AFAbfe95Fd2B04;
    address public           _burnAddress           = 0x000000000000000000000000000000000000dEaD;

    uint256 constant _rewardRateForTreasury         = 2;
    uint256 constant _rewardRateForStake            = 7;
    uint256 constant _rewardRateForLiquidity        = 1;
    uint256 constant REWARD_NODE_PER_SECOND         = 225 * 10**15 / (uint256)(3600 * 24);  // 0.225
    uint256 constant REWARD_MASTER_NFT_PER_SECOND   = 25 * 10**15 / (uint256)(3600 * 24);   // 0.025
    uint256 constant REWARD_GRAND_NFT_PER_SECOND    = 50 * 10**15 / (uint256)(3600 * 24);   // 0.05
    uint256 constant NODE_PRICE                     = 10 * 10**18;                          // 10 FIRE
    uint256 constant MASTER_NFT_PRICE               = 10 * 10**18;                          // 10 FIRE
    uint256 constant GRAND_NFT_PRICE                = 100 * 10**18;                         // 100 FIRE
    uint256 constant NODECOUNT_PER_MASTERNFT        = 10;                                   // 10 NODE
    uint256 constant NODECOUNT_PER_GRANDNFT         = 100;                                  // 100 NODE
    uint256 constant MAX_NODE_PER_USER              = 100;                                  // 100 NODE
    uint256 constant ONE_MONTH_TIME                 = 2592000000;                           // seconds for one month
    uint256 THREE_MONTH_PRICE                       = 20 * 10**18;                      // 40 USD
    uint256 CLAIM_FEE                               = 5 * 10**18;                           // 5 USD

    FireToken public _tokenContract;
    FireNFT public _nftContract;
    
    IERC20 private _usdcToken;

    mapping(address => uint256) private _rewardsOfUser;
    mapping(address => NodeInfo[]) private _nodesOfUser;
    mapping(address => NFTInfo[]) private _nftOfUser;
    
    constructor(FireToken tokenContract, FireNFT nftContract) { 
        _tokenContract = tokenContract;
        _nftContract = nftContract;
        _joe02Router = IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        _usdcToken = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);
        pauseContract = 0;
    }

    function getNodePrice() public view returns (uint256) {
        return NODE_PRICE;
    }

    function getContractStatus() public view returns (uint256) {
        return pauseContract;
    }

    function setContractStatus(uint256 _newPauseContract) public onlyOwner {
        pauseContract = _newPauseContract;
    }    

    function getNodeMaintenanceFee() public view returns (uint256) {
        return THREE_MONTH_PRICE;
    }

    function setNodeMaintenanceFee(uint256 _newThreeMonthFee) public onlyOwner {
        THREE_MONTH_PRICE = _newThreeMonthFee;
    }

    function getMasterNFTPrice() public view returns (uint256) {
        return getAvaxForFire(MASTER_NFT_PRICE);
    }

    function getGrandNFTPrice() public view returns (uint256) {
        return getAvaxForFire(GRAND_NFT_PRICE);
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

    function getTreasuryAmount() public returns(uint){
        return address(_treasuryWallet).balance;
    }

    function getTreasuryRate() public returns(uint){
        uint256 total_balance = address(_treasuryWallet).balance;
        return total_balance.div(_tokenContract.balanceOf(address(this)));
    }

    function quickSort(uint[] memory arr, uint left, uint right) private {
        uint i = left;
        uint j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                if(j==0) {
                    break;
                }
                j--;
            }
        }
        if (left < j)
            quickSort(arr, left, j);
        if (i < right)
            quickSort(arr, i, right);
    }

    function getIntervalArrays(address addr) private view returns(uint256[] memory){
        NodeInfo[] memory nodes = _nodesOfUser[addr];
        NFTInfo[] memory nfts = _nftOfUser[addr];
        uint256[] memory result = new uint256[](nodes.length * 2 + nfts.length + 1);
        uint i=0;
        uint j=0;
        uint total=0;
        uint256 currentTime = block.timestamp;

        for(; i<nodes.length; i++) {
            result[total++] = Math.min(nodes[i].createTime, currentTime);
            result[total++] = Math.min(nodes[i].lastTime, currentTime);            
        }

        for(j=0; j<nfts.length; j++) {
            result[total+j] = nfts[j].createTime;
        }
        
        result[total+j] = currentTime;
        quickSort(result, 0, result.length-1);
        uint256 prevValue = 0;
        j=0;
        for(i=0; i<result.length; i++) {
            if(prevValue != result[i]) {
                prevValue = result[i];
                j++;
            }
        }
        uint256[] memory uniqueResult = new uint256[](j);
        prevValue = 0;
        j=0;
        for(i=0; i<result.length; i++) {
            if(prevValue != result[i]) {
                uniqueResult[j] = result[i];
                prevValue = result[i];
                j++;
            }
        }
        return uniqueResult;
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

    function buyNode(uint256 numberOfNodes) public payable{
        require(pauseContract == 0, "Contract Paused");

        uint256 numberOfTokens = numberOfNodes * NODE_PRICE;
        uint256 prevNumberOfNode = _nodesOfUser[msg.sender].length;
        require(_tokenContract.balanceOf(msg.sender) >= numberOfTokens, "user doesn't have enough token balance");
        require(_treasuryWallet != msg.sender, "can't buy using treasury's address");
        require(prevNumberOfNode + numberOfNodes <= MAX_NODE_PER_USER, "can't buy more than 100 nodes");
        
        // send 8 Fire to RewardPool: 7 Fire for rewardPool, 1 Fire for liquidity
        uint256 numberOfStaking = numberOfTokens * _rewardRateForStake/10;
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
        uint256 payVal = getAvaxForUSD(THREE_MONTH_PRICE) * numberOfNodes;
        require(msg.sender.balance >= payVal, "no enough balance");
        _maintenanceWallet.transfer(payVal);

        // emit purchased node event
        PurchasedNode(msg.sender, numberOfNodes);
    }

    function getAvailableNodes(address addr, uint256 checkTime) internal view returns(uint) {
        NodeInfo[] memory nodes = _nodesOfUser[addr]; 
        uint res = 0;
        for(uint i=0; i<nodes.length; i++) {
            if(nodes[i].createTime <= checkTime && checkTime <= nodes[i].lastTime) {
                res++;
            }
        }
        return res;
    }

    function buyNFT(NFT_TYPE typeOfNFT, uint nftCount) public payable{
        require(pauseContract == 0, "Contract Paused");

        address addr = msg.sender;
        uint avNodeCount = getAvailableNodes(addr, block.timestamp);
        uint prevNFTCount = _nftOfUser[addr].length;
        uint MAX_MASTER_NFT_COUNT = NODECOUNT_PER_GRANDNFT / NODECOUNT_PER_MASTERNFT;
        uint prevMasterNFTCount = prevNFTCount == MAX_MASTER_NFT_COUNT+1 ? MAX_MASTER_NFT_COUNT : prevNFTCount;
        uint prevGrandNFTCount = prevNFTCount == MAX_MASTER_NFT_COUNT+1 ? 1 : 0;
        uint remainNodeCount = avNodeCount - prevMasterNFTCount * NODECOUNT_PER_MASTERNFT;
        uint256 nftPrice;
        if(typeOfNFT == NFT_TYPE.GRAND_NFT) {
            require(prevGrandNFTCount == 0, "have already grand nft");
            require(nftCount == 1, "buy only 1 grand nft");
            require(prevMasterNFTCount == MAX_MASTER_NFT_COUNT, "no need grand nft for now");
            nftPrice = GRAND_NFT_PRICE;
        } else {
            require(avNodeCount >= prevMasterNFTCount * NODECOUNT_PER_MASTERNFT, "no need so many master");
            require(remainNodeCount / NODECOUNT_PER_MASTERNFT >= nftCount, "no need so many master nft");
            require(prevMasterNFTCount + nftCount <=MAX_MASTER_NFT_COUNT, "no need more than 10 master nft");
            nftPrice = MASTER_NFT_PRICE;
        }
        // payment with avax
        uint256 amountForAvax = getAvaxForFire(nftPrice) * nftCount;
        require(msg.sender.balance >= amountForAvax, "no enouth AVAX");
        _maintenanceWallet.transfer(amountForAvax);        
        
        for(uint i=0; i<nftCount; i++) {
            _nftContract.mintNFT(msg.sender, uint256(typeOfNFT));
            _nftOfUser[addr].push(NFTInfo({createTime: block.timestamp, typeOfNFT : typeOfNFT}));
        }
    }

    function payNodeFee(uint256 nodeId, MODE_FEE feeMode) public payable{
        require(pauseContract == 0, "Contract Paused");

        address payable addr = msg.sender;
        uint256 payVal;
        require(block.timestamp <= _nodesOfUser[addr][nodeId].lastTime, "deleted node");
        require(block.timestamp + ONE_MONTH_TIME> _nodesOfUser[addr][nodeId].lastTime, "already purchased");
        
        if(feeMode == MODE_FEE.THREE_MONTH) {
            payVal = getAvaxForUSD(THREE_MONTH_PRICE);
            require(addr.balance >= payVal, "no enough balance");
            _nodesOfUser[addr][nodeId].lastTime += 3 * ONE_MONTH_TIME;
        } else if(feeMode == MODE_FEE.SIX_MONTH) {
            payVal = getAvaxForUSD(THREE_MONTH_PRICE * 2);
            require(addr.balance >= payVal, "no enough balance");
            _nodesOfUser[addr][nodeId].lastTime += 6 * ONE_MONTH_TIME;
        }
        _maintenanceWallet.transfer(payVal);
    }

    function deleteNodesOfUser(address addr, bool[] memory enableAry) internal{
        NodeInfo[] memory nodes = _nodesOfUser[addr];
        for(uint i=enableAry.length-1; i>=0; i--) {
            if(enableAry[i] == false) {
                if(i != nodes.length - 1) {
                    nodes[i] = nodes[nodes.length-1];
                }
                delete nodes[nodes.length-1];
            }
        }
    }
    function claimByNode(uint256 nodeId) public payable{
        require(pauseContract == 0, "Contract Paused");

        require(_nodesOfUser[msg.sender].length > nodeId, "invalid Node ID");
        
        uint256 fiveDolorAvax = getAvaxForUSD(CLAIM_FEE);
        require(msg.sender.balance >= fiveDolorAvax, "no enough balance");

        RewardInfo memory rwInfo = getRewardAmount(msg.sender);
        NodeInfo[] memory nodes = _nodesOfUser[msg.sender];
        
        // add rewards and initialize timestamp for all enabled nodes
        for(uint i=0; i<rwInfo.enableNode.length; i++) {
            if(rwInfo.enableNode[i] == true) {
                if(i==nodeId) {
                    nodes[i].reward = 0;
                } else {
                    nodes[i].reward = rwInfo.nodeRewards[i];
                }
                nodes[i].createTime = block.timestamp;
            }
        }
        // send FireToken rewards of nodeId to msg.sender
        _tokenContract.transfer(msg.sender, rwInfo.nodeRewards[nodeId]);

        // delete all disabled nodes
        deleteNodesOfUser(msg.sender, rwInfo.enableNode);
        
        // fee payment 5$ to do
        _maintenanceWallet.transfer(fiveDolorAvax);
    }

    function claimAll() public payable{
        require(pauseContract == 0, "Contract Paused");
        
        RewardInfo memory rwInfo = getRewardAmount(msg.sender);
        uint256 rewards = 0;
        uint nEnableCount = 0;
        for(uint i=0; i<rwInfo.nodeRewards.length; i++) {
            if(rwInfo.enableNode[i] == true) {
                nEnableCount++;
            }
        }
        
        // fee payment 5$ to do
        uint256 totalFiveDolorAvax = getAvaxForUSD(CLAIM_FEE).mul(nEnableCount);
        require(msg.sender.balance >= totalFiveDolorAvax, "no enough balance for claim fee");
        _maintenanceWallet.transfer(totalFiveDolorAvax);

        for(uint i=0; i<rwInfo.nodeRewards.length; i++) {
            if(rwInfo.enableNode[i] == true) {
                rewards += rwInfo.nodeRewards[i];
                _nodesOfUser[msg.sender][i].reward = 0;
                _nodesOfUser[msg.sender][i].createTime = block.timestamp;
            }
        }

        // send FireToken rewards to msg.sender
        _tokenContract.transfer(msg.sender, rewards);

        // delete all disabled nodes
        deleteNodesOfUser(msg.sender, rwInfo.enableNode);

    }

    function getNodeList(address addr) view public returns(NodeInfo[] memory result){
        result = _nodesOfUser[addr];
        return result;
    }

    function getNFTList(address addr) view public returns(NFTInfo[] memory result){
        result = _nftOfUser[addr];
        return result;
    }

    function getRewardAmount(address addr) view public returns(RewardInfo memory){
        require(pauseContract == 0, "Contract Paused");

        NFTInfo[] memory nfts = _nftOfUser[addr];
        NodeInfo[] memory nodes = _nodesOfUser[addr];

        RewardInfo memory rwInfo;
        rwInfo.rewardBalance = _rewardsOfUser[addr];
        rwInfo.nodeRewards = new uint256[](nodes.length);
        rwInfo.enableNode = new bool[](nodes.length);
        rwInfo.curMasterNFTEnable = new bool[](nodes.length);
        rwInfo.curGrandNFTEnable = new bool[](nodes.length);
        uint256 duringTime;
        //calculate node reward
        for(uint256 i=0; i<nodes.length; i++) {
            rwInfo.enableNode[i] = nodes[i].lastTime >= block.timestamp ? true : false;
            duringTime = 0;

            if( rwInfo.enableNode[i] == true )
                duringTime = (Math.min(nodes[i].lastTime, block.timestamp) - nodes[i].createTime);

            rwInfo.nodeRewards[i] = nodes[i].reward + duringTime * REWARD_NODE_PER_SECOND;
            
            rwInfo.curMasterNFTEnable[i] = false;
            rwInfo.curGrandNFTEnable[i] = false;
        }
        // calculate master nft reward
        uint256[] memory uniqueResult = getIntervalArrays(addr);

        uint256 masterNftCount;
        uint256 grandNftCount;
        uint256 enableNodeCount;
        for(uint i=1; i<uniqueResult.length; i++) {
            //calculate nft count
            masterNftCount = 0;
            grandNftCount = 0;
            for(uint j=0; j<nfts.length; j++) {
                if(nfts[j].createTime <= uniqueResult[i-1]){
                    if(nfts[j].typeOfNFT == NFT_TYPE.MASTER_NFT) {
                        masterNftCount++;
                    } else if(nfts[j].typeOfNFT == NFT_TYPE.GRAND_NFT) {
                        grandNftCount++;
                    }
                }
            }

            //calculate node count
            uint[] memory allownodes = new uint[](nodes.length);
            enableNodeCount = 0;
            for(uint j=0; j<nodes.length; j++) {
                if(nodes[j].createTime <= uniqueResult[i-1] && nodes[j].lastTime >= uniqueResult[i]) {
                    allownodes[enableNodeCount] = j;
                    enableNodeCount++;
                }
            }

            //node count for nft applying
            uint256 enableMasterNftCount = Math.min(masterNftCount, SafeMath.div(enableNodeCount, NODECOUNT_PER_MASTERNFT));
            uint256 enableGrandNftCount = Math.min(grandNftCount, SafeMath.div(enableNodeCount, NODECOUNT_PER_MASTERNFT));

            //calculate master nft rewards per nodes
            uint nodeId;
            for(uint j=0; j<enableMasterNftCount * NODECOUNT_PER_MASTERNFT; j++) {
                nodeId = allownodes[j];
                rwInfo.nodeRewards[nodeId] += (uniqueResult[i] - uniqueResult[i-1]) * REWARD_MASTER_NFT_PER_SECOND;
                if(i==uniqueResult.length - 1) {
                    rwInfo.curMasterNFTEnable[nodeId] = true;
                }
            }
            //calculate grand nft rewards per nodes
            for(uint j=0; j<enableGrandNftCount * NODECOUNT_PER_GRANDNFT; j++) {
                nodeId = allownodes[j];
                rwInfo.nodeRewards[nodeId] += (uniqueResult[i] - uniqueResult[i-1]) * REWARD_GRAND_NFT_PER_SECOND;
                if(i==uniqueResult.length - 1) {
                    rwInfo.curGrandNFTEnable[nodeId] = true;
                }
            }
        }
        return rwInfo;
    }
}