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
    event Split(uint256 indexed tokenId, uint256 amount, address to);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(
        address _token,
        address _veNFT,
        address _voter,
        address _rewardDistributor,
        address _externalDistributor,
        uint _lockingYear  // eg.: crv = 4, lqdr = 2
    ) {
        token = _token;
        veNFT = _veNFT;
        require(_token == IVotingEscrow(veNFT).token(), 'not same token');
        
        voter = _voter;
        rewardDistributor = _rewardDistributor;
        externalDistributor = _externalDistributor;

        MAX_TIME = _lockingYear * 364 * 86400;
        WEEK = 7 * 86400;
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
        IVotingEscrow(veNFT).setApprovalForAll(_liquidToken, true);
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

    /**
     * @dev Splits the main veNFT and transfers the new NFT to the specified recipient
     * @param _tokenId veNFT identifier 
     * @param _amountToSplit The amount of underlying tokens to split off
     * @param _recipient The address to receive the split NFT
     * @return newTokenId The ID of the new NFT created by the split
     */
    function splitAndSend(uint256 _tokenId, uint256 _amountToSplit, address _recipient) external onlyLiquidToken returns (uint256 newTokenId) {
        // Get the current balance of the main veNFT
        uint256 totalBalance = uint256(uint128(IVotingEscrow(veNFT).locked(_tokenId).amount));
        
        // Ensure we're not trying to split more than available
        require(_amountToSplit > 0 && _amountToSplit < totalBalance, "Invalid split amount");
        
        // Make sure the resulting split is meaningful (at least 1% of the total)
        require(_amountToSplit >= totalBalance / 100, "Split amount too small");
        
        // Make sure the remaining amount is also meaningful
        uint256 remainingBalance = totalBalance - _amountToSplit;
        require(remainingBalance >= totalBalance / 100, "Remaining amount too small");
        
        // Prepare the amounts array for the split
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = remainingBalance; // Amount to keep in the original NFT
        amounts[1] = _amountToSplit;   // Amount to send to recipient
        
        // Count NFTs before split
        uint256 nftCountBefore = IVotingEscrow(veNFT).balanceOf(address(this));
        
        // Execute the split
        try IVotingEscrow(veNFT).split(amounts, _tokenId) {
            // Count NFTs after split
            uint256 nftCountAfter = IVotingEscrow(veNFT).balanceOf(address(this));
            
            // Verify split was successful
            require(nftCountAfter == nftCountBefore + 1, "Split failed");
            
            // Get the IDs of the NFTs after split
            // The original tokenId remains with the first amount, and a new NFT is created for the second amount
            uint256 newNftIndex = nftCountAfter - 1; // Index of the newly created NFT
            newTokenId = IVotingEscrow(veNFT).tokenOfOwnerByIndex(address(this), newNftIndex);
            
            // Transfer the new NFT to the recipient
            IVotingEscrow(veNFT).transferFrom(address(this), _recipient, newTokenId);
            
            emit Split(_tokenId, _amountToSplit, _recipient);
            
            return newTokenId;
        } catch {
            // If the split fails, revert with a clearer message
            revert("NFT split operation failed - check your vesting contract's requirements");
        }
    }

    function resetVote() external onlyVoter {
        IVoter(voter).reset(tokenId);
    }

    function getVeNFTExpirationInWeeks(uint256 _tokenId) private view returns (uint256 expirationInWeeks) {
        // Get the lock end time from the veNFT contract
        uint256 lockEndTime = IVotingEscrow(veNFT).locked__end(_tokenId);
        
        // Ensure the lock hasn't already expired
        require(lockEndTime > block.timestamp, "Invalid veNFT: lock already expired");
        
        // Calculate remaining time in seconds
        uint256 timeRemaining = lockEndTime - block.timestamp;
        
        // Convert to weeks, rounded up (hence adding WEEK-1)
        expirationInWeeks = (timeRemaining + WEEK - 1) / WEEK;
        
        // Ensure minimum of 1 week to prevent divide-by-zero issues elsewhere
        expirationInWeeks = expirationInWeeks < 1 ? 1 : expirationInWeeks;
        
        return expirationInWeeks;
    }

    function handleDeposit(uint256 _tokenId) external onlyLiquidToken {
        // Verify the token is already owned by this contract
        address tokenOwner = IVotingEscrow(veNFT).ownerOf(_tokenId);
        require(tokenOwner == address(this), "Token not owned by this contract");
        
        // Get the lock end time for the deposited NFT
        uint256 depositedLockEndTime = IVotingEscrow(veNFT).locked__end(_tokenId);
        
        // Ensure the lock hasn't already expired
        require(depositedLockEndTime > block.timestamp, "Invalid veNFT: lock already expired");
        
        // Get all veNFTs owned by this contract
        uint256 ownedCount = IVotingEscrow(veNFT).balanceOf(address(this));
        
        // If we don't own any other veNFTs yet, no merge, just keep the new veNFT as is
        if (ownedCount <= 1) return;
        
        // Find a veNFT that expires within 1 week of our deposited NFT
        for (uint256 i = 0; i < ownedCount; i++) {
            uint256 currentTokenId = IVotingEscrow(veNFT).tokenOfOwnerByIndex(address(this), i);
            
            // Skip the token we just deposited
            if (currentTokenId == _tokenId) continue;
            
            // Get lock end time of the current token
            uint256 currentLockEndTime = IVotingEscrow(veNFT).locked__end(currentTokenId);
            
            // We only consider tokens that expire LATER than (older than) our deposit token
            if (currentLockEndTime > depositedLockEndTime) {
                // Calculate time difference in seconds
                uint256 timeDifference = currentLockEndTime - depositedLockEndTime;
                
                // If the difference is within 1 week, merge and exit
                if (timeDifference <= 1 * WEEK) {
                    IVotingEscrow(veNFT).merge(currentTokenId, _tokenId);
                    return; // Merge complete, exit the function
                }
            }
        }
        
        // If we reach here, we didn't find any suitable match, so we just keep the veNFT as is
    }
}