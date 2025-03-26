// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
// Removed Ownable import

import "../interfaces/IVotingEscrow.sol";
import "../interfaces/IVoter.sol";
import "../interfaces/IRewardsDistributor.sol";
// import "./interfaces/ILiveTheManager.sol";

contract SolidlyStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    struct VoteInfo {
        address[] pairs;
        uint256[] weights;
    }
    
    VoteInfo lastVote;
    
    address public veNFT;
    address public token;
    address public liquidToken;
    address public voter;
    address public rewardDistributor;
    address public externalDistributor;

    uint256 public tokenId;
    uint256 public MAX_TIME;
    uint256 public WEEK;

    mapping(uint256 => uint256) public tokenIdAt;
    mapping(uint256 => VoteInfo) voteInfoAt;

    event Merge(uint256 indexed from);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(
        address _token,
        address _veNFT,
        address _voter,
        address _rewardDistributor,
        address _externalDistributor,
        uint _lockingYear   // eg.: crv = 4, lqdr = 2
    ) {
        token = _token;
        veNFT = _veNFT;
        require(_token == IVotingEscrow(veNFT).token(), 'not same token');
        
        voter = _voter;
        rewardDistributor = _rewardDistributor;
        externalDistributor = _externalDistributor;

        MAX_TIME = _lockingYear * 364 * 86400;
        WEEK = 7 * 86400;
        IVotingEscrow(veNFT).setApprovalForAll(liquidToken, true);
    }

    modifier onlyLiquidToken {
        require(msg.sender == liquidToken, "Auth failed");
        _;
    }

    modifier onlyVoter {
        require(msg.sender == voter, "Only voter can call");
        _;
    }

    function getLastVote() external view returns (VoteInfo memory) {
        return lastVote;
    }

    /*
        -------------------
        Setters
        -------------------
    */

    function setLiquidToken (address _liquidToken) external {
        require(liquidToken == address(0), 'addr 0');
        liquidToken = _liquidToken;
    }

    function setVoter(address _voter) external onlyVoter {
        require(_voter != address(0), 'addr 0');
        voter = _voter;
    }

    /*  
        -------------------
        veNFT MANAGMENT
        -------------------
    */

    function createLock(uint256 _amount, uint256 _unlockTime) external onlyLiquidToken {
        uint256 _balance = IERC20(token).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds balance");
        IERC20(token).approve(veNFT, 0);
        IERC20(token).approve(veNFT, _amount);
        tokenId = IVotingEscrow(veNFT).create_lock(_amount, _unlockTime);
    }

    function release() external onlyLiquidToken {
        IVotingEscrow(veNFT).withdraw(tokenId);
    }

    function increaseAmount(uint256 _amount) external onlyLiquidToken {
        uint256 _balance = IERC20(token).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds token balance");
        IERC20(token).approve(veNFT, 0);
        IERC20(token).approve(veNFT, _amount);
        IVotingEscrow(veNFT).increase_amount(tokenId, _amount);
    }

    function _increaseTime(uint256 _unlockTime) internal {
        IVotingEscrow(veNFT).increase_unlock_time(tokenId, _unlockTime);
    }

    function increaseTime(uint256 _unlockTime) external {
        _increaseTime(_unlockTime);
    }

    function increaseTimeMax() external {
        _increaseTime(MAX_TIME);
    }

    function balanceOfveNFT() public view returns (uint256) {
        return IVotingEscrow(veNFT).balanceOfNFT(tokenId);
    }

    /*  
        -------------------
        VOTING AND CLAIMING
        -------------------
    */

    function claimBribe(
        address[] memory _bribes,
        address[][] memory _tokens
    ) external {
        IVoter(voter).claimBribes(_bribes, _tokens, tokenId);
        
        // Flatten the 2D array of tokens and send all balances
        for(uint i = 0; i < _tokens.length; i++) {
            sendAllToRewardDistributor(_tokens[i]);
        }
    }

    function claimFees(address[] memory _fees, address[][] memory _tokens) external {
        IVoter(voter).claimFees(_fees, _tokens, tokenId);
    }

    function claimRebase() external {
        IRewardsDistributor(externalDistributor).claim(tokenId);
    }

    function sendAllToRewardDistributor(address[] memory _tokens) public {
        uint256 i = 0;
        uint256 _amount = 0;
        address _token;
        for(i; i < _tokens.length; i++){
            _token = _tokens[i];
            _amount = IERC20(_token).balanceOf(address(this));
            if(_amount > 0){
                IERC20(_token).safeTransfer(rewardDistributor, _amount);
            }
        }
    }

    function vote(address[] calldata _pool, uint256[] calldata _weights) external onlyVoter {
        require(_pool.length == _weights.length, "Token length doesn't match");
        uint256 _length = _pool.length;
        IVoter(voter).vote(tokenId, _pool, _weights);

        VoteInfo memory _lastVote;
        _lastVote.pairs = new address[](_length);
        _lastVote.pairs = _pool;

        _lastVote.weights = new uint[](_length);
        _lastVote.weights = _weights;

        lastVote = _lastVote;

        // ILiveTheManager(liveTheManager).disableRedeem();

        // tokenIdAt[ILiveTheManager(liveTheManager).getCurrentEpoch()] = tokenId;
        // voteInfoAt[ILiveTheManager(liveTheManager).getCurrentEpoch()] = lastVote;
    }

    function merge(uint256 from) external onlyLiquidToken {
        require(from != tokenId, "Can't merge from main tokenId");
        IVotingEscrow(veNFT).merge(from, tokenId);
        emit Merge(from);
    }

    function splitAndSend(uint256 _toSplit, address _to) external onlyLiquidToken {
        uint256 _totalNftBefore = IVotingEscrow(veNFT).balanceOf(address(this));
        uint256 _totalBalance = balanceOfveNFT();
        uint256 _totalBalanceAfter = _totalBalance - _toSplit;
        uint256[] memory _amounts = new uint[](2);
        _amounts[0] = _totalBalanceAfter;
        _amounts[1] = _toSplit;

        IVotingEscrow(veNFT).split(_amounts, tokenId);

        uint256 _totalNftAfter = IVotingEscrow(veNFT).balanceOf(address(this));
        require(_totalNftAfter == _totalNftBefore + 1, "Failed split.");

        uint256 _tokenId1 = IVotingEscrow(veNFT).tokenOfOwnerByIndex(
            address(this),
            _totalNftAfter - 1
        );
        uint256 _tokenId0 = IVotingEscrow(veNFT).tokenOfOwnerByIndex(
            address(this), 
            _totalNftAfter - 2
        );

        tokenId = _tokenId0;
        IVotingEscrow(veNFT).transferFrom(address(this), _to, _tokenId1);
    }

    function resetVote() external onlyVoter {
        IVoter(voter).reset(tokenId);
    }


    function getVeNFTAgeInWeeks(uint256 _tokenId) public view returns (uint256 ageInWeeks) {
        // uint256 lockEndTime = IVotingEscrow(veNFT).locked__end(_tokenId);
        uint256 creationTime = IVotingEscrow(veNFT).user_point_history__ts(_tokenId, 0);
        require(creationTime > 0, "Invalid veNFT: creation time is zero");
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime > creationTime ? currentTime - creationTime : 0;
        ageInWeeks = timeElapsed / WEEK;
        
        return ageInWeeks;
    }
}