// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IVeThe.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/ILiveTheManager.sol";
import "./interfaces/IThenaBribes.sol";

contract LiveTheStrategy is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    string public __NAME__;
    struct VoteInfo{
        address[] pairs;
        uint256[] weights;
    }
    
    VoteInfo lastVote;
    
    address public veThe;
    address public thena;
    address public liveTheManager;
    address public thenaVoter;
    address public feeManager;
    address public thenaRewardsDistributor;

    mapping(address => bool) isBoostStrategy;
    mapping(address => bool) public isAllowedVoter;

    uint256 public tokenId;
    uint256 public MAX_TIME;
    uint256 public WEEK;

    mapping(uint256 => uint256) public tokenIdAt;
    mapping(uint256 => VoteInfo) voteInfoAt;

    address public manualFeeManager;
    bool public isManual;

    event Merge(uint256 indexed from);

    constructor() public {}

    function initialize(
        string memory _name,
        address _thena,
        address _veThe,
        address _thenaVoter,
        address _feeManager,
        address _thenaRewardsDistributor,
        uint _lockingYear   // eg.: crv = 4, lqdr = 2
    ) public initializer {
        __Ownable_init();
        __NAME__ = _name;

        thena = _thena;
        veThe = _veThe;
        require(_thena == IVeThe(veThe).token(), 'not same token');
        
        thenaVoter = _thenaVoter;
        feeManager = _feeManager;
        thenaRewardsDistributor = _thenaRewardsDistributor;

        MAX_TIME = _lockingYear * 364 * 86400;
        WEEK = 7 * 86400;
    }

    modifier restricted {
        require(msg.sender == owner() || msg.sender == liveTheManager, "Auth failed");
        _;
    }

    modifier ownerOrAllowedVoter {
        require(msg.sender == owner() || isAllowedVoter[msg.sender], "Permission denied");
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

    function setVoter(address _voter) external onlyOwner {
        require(_voter != address(0), 'addr 0');
        thenaVoter = _voter;
    }

    function setThenaRewardsDistributor(address _thenaRewardsDistributor) external onlyOwner {
        require(_thenaRewardsDistributor != address(0), 'addr 0');
        thenaRewardsDistributor = _thenaRewardsDistributor;
    }

    function setLiveTheManager(address _manager) external onlyOwner {
        require(_manager != address(0), 'addr 0');
        liveTheManager = _manager;
    }

    function whitelistVoter(address _voter) external onlyOwner {
        isAllowedVoter[_voter] = true;
    }

    function blacklistVoter(address _voter) external onlyOwner {
        isAllowedVoter[_voter] = false;
    }

    function setManualFeeManager(address _manager) external onlyOwner {
        require(_manager != address(0), 'addr 0');
        manualFeeManager = _manager;
    }

    function setIsManual(bool _isManual) external onlyOwner {
        isManual = _isManual;
    }

    /*  
        -------------------
        veThe MANAGMENT
        -------------------
    */

    function createLock(uint256 _amount, uint256 _unlockTime) external restricted {
        uint256 _balance = IERC20(thena).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds balance");
        IERC20(thena).safeApprove(veThe, 0);
        IERC20(thena).safeApprove(veThe, _amount);
        tokenId = IVeThe(veThe).create_lock(_amount, _unlockTime);
    }

    function release() external restricted {
        IVeThe(veThe).withdraw(tokenId);
    }

    function increaseAmount(uint256 _amount) external restricted {
        uint256 _balance = IERC20(thena).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds thena balance");
        IERC20(thena).safeApprove(veThe, 0);
        IERC20(thena).safeApprove(veThe, _amount);
        IVeThe(veThe).increase_amount(tokenId, _amount);
    }

    function _increaseTime(uint256 _unlockTime) internal {
        IVeThe(veThe).increase_unlock_time(tokenId, _unlockTime);
    }

    function increaseTime(uint256 _unlockTime) external onlyOwner {
        _increaseTime(_unlockTime);
    }

    function increaseTimeMax() external {
        _increaseTime(MAX_TIME);
    }

    function balanceOfVeThe() public view returns (uint256) {
        return IVeThe(veThe).balanceOfNFT(tokenId);
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
        IVoter(thenaVoter).claimBribes(_bribes, _tokens, tokenId);
        uint256 i = 0;
        uint256 k = 0;
        uint256 _len1 = _bribes.length;
        uint256 _len2;
        uint256 _amount = 0;
        address _token;
        for(i; i < _len1; i++){
            _len2 = _tokens[i].length;
            for(k = 0; k < _len2; k++){
                _token = _tokens[i][k];
                _amount = IERC20(_token).balanceOf(address(this));
                if(_amount > 0){
                    if (isManual && manualFeeManager != address(0)) {
                        IERC20(_token).safeTransfer(manualFeeManager, _amount);
                    }
                    else {
                        IERC20(_token).safeTransfer(feeManager, _amount);
                    }
                }
            }
        }
    }

    function claimFees(address[] memory _fees, address[][] memory _tokens) external {
        IVoter(thenaVoter).claimFees(_fees, _tokens, tokenId);
        uint256 i = 0;
        uint256 k = 0;
        uint256 _len1 = _fees.length;
        uint256 _len2;
        uint256 _amount = 0;
        address _token;
        for(i; i < _len1; i++){
            _len2 = _tokens[i].length;
            for(k = 0; k < _len2; k++){
                _token = _tokens[i][k];
                _amount = IERC20(_token).balanceOf(address(this));
                if(_amount > 0){
                    if (isManual && manualFeeManager != address(0)) {
                        IERC20(_token).safeTransfer(manualFeeManager, _amount);
                    }
                    else {
                        IERC20(_token).safeTransfer(feeManager, _amount);
                    }
                }
            }
        }
    }

    function claimRebase() external restricted {
        IRewardsDistributor(thenaRewardsDistributor).claim(tokenId);
        _resetVote();
    }

    function vote(address[] calldata _pool, uint256[] calldata _weights) external ownerOrAllowedVoter {
        require(_pool.length == _weights.length, "Token length doesn't match");
        uint256 _length = _pool.length;
        IVoter(thenaVoter).vote(tokenId, _pool, _weights);

        VoteInfo memory _lastVote;
        _lastVote.pairs = new address[](_length);
        _lastVote.pairs = _pool;

        _lastVote.weights = new uint[](_length);
        _lastVote.weights = _weights;

        lastVote = _lastVote;

        ILiveTheManager(liveTheManager).disableRedeem();

        tokenIdAt[ILiveTheManager(liveTheManager).getCurrentEpoch()] = tokenId;
        voteInfoAt[ILiveTheManager(liveTheManager).getCurrentEpoch()] = lastVote;
    }

    function merge(uint256 from) external restricted {
        require(from != tokenId, "Can't merge from main tokenId");
        IVeThe(veThe).merge(from, tokenId);
        emit Merge(from);
    }

    function splitAndSend(uint256 _toSplit, address _to) external restricted {
        uint256 _totalNftBefore = IVeThe(veThe).balanceOf(address(this));
        uint256 _totalBalance = balanceOfVeThe();
        uint256 _totalBalanceAfter = _totalBalance.sub(_toSplit);
        uint256[] memory _amounts = new uint[](2);
        _amounts[0] = _totalBalanceAfter;
        _amounts[1] = _toSplit;

        IVeThe(veThe).split(_amounts, tokenId);

        uint256 _totalNftAfter = IVeThe(veThe).balanceOf(address(this));
        require(_totalNftAfter == _totalNftBefore + 1, "Failed split.");

        uint256 _tokenId1 = IVeThe(veThe).tokenOfOwnerByIndex(
            address(this),
            _totalNftAfter - 1
        );
        uint256 _tokenId0 = IVeThe(veThe).tokenOfOwnerByIndex(
            address(this), 
            _totalNftAfter - 2
        );

        tokenId = _tokenId0;
        IVeThe(veThe).transferFrom(address(this), _to, _tokenId1);
    }

    function _resetVote() internal {
        IVoter(thenaVoter).reset(tokenId);
    }

    function resetVote() external onlyOwner {
        _resetVote();
    }
}