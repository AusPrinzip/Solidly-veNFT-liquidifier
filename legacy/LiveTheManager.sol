// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ILiveTheStrategy.sol";
import "./interfaces/ILiveThe.sol";
import "./interfaces/IThenaPair.sol";
import "./interfaces/ILiveTheFeeManager.sol";
import "./interfaces/IVeThe.sol";
import "./SmartWalletWhitelist.sol";

contract LiveTheManager is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    string public __NAME__;
    address public thena;
    uint256 public MAXTIME;
    uint256 public WEEK;
    uint256 public MIN_VE_DEPOSIT_FEE;
    uint256 public MAX_VE_DEPOSIT_FEE;

    address public feeManager;
    address public strategy;
    address public liveThe;
    address public veThe;

    address public thenaPair;

    address public smartWalletWhitelist;

    bool public veDepositEnabled;
    bool public isPromotionPeriod;
    uint256 public PROMO_VE_DEPOSIT_FEE;
    uint256 public MULTIPLIER;
    uint256 public REDEEM_FEE;

    uint256 public beginTimestamp;

    uint256 public supplyPercentageLimit;

    uint256 public liveTheSupplyAtCurrentEpoch;

    mapping(uint256 => uint256) public mintedFromNftAt;
    bool public redeemEnabled;

    mapping(address => bool) public isOperator;

    event InitialLock(uint256 unlockTime);
    event IncreaseAmount(uint256 amount);
    event SetPromotionPeriod(bool set, uint256 fee);
    event SetBeginTimestamp(uint256 timestamp);
    event Deposit(address indexed sender, uint256 amount);
    event DepositNFT(address indexed sender, uint256 tokenId, uint256 amount);
    event Redeem(address indexed sender, uint256 amount, uint256 redeemed);
    event SetThenaPair(address pair);
    event EnableVeTheDeposit();
    event DisableVeTheDeposit();
    event Rebase(uint amount);

    constructor() public {}

    function initialize(
        string memory _name,
        address _strategy,
        address _liveThe,
        address _thena,
        address _veThe,
        address _thenaPair,
        address _smartWalletWhitelist,
        address _feeManager,
        uint _lockingYear // eg.: crv = 4, lqdr = 2
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __NAME__ = _name;
        feeManager = _feeManager;
        strategy = _strategy;

        liveThe = _liveThe;
        veThe = _veThe;

        thenaPair = _thenaPair;

        MAXTIME = _lockingYear * 364 * 86400;
        WEEK = 7 * 86400;
        thena = _thena;

        veDepositEnabled = true;
        isPromotionPeriod = false;

        MIN_VE_DEPOSIT_FEE = 125;
        MAX_VE_DEPOSIT_FEE = 700;
        MULTIPLIER = 1000;

        supplyPercentageLimit = 150;
        REDEEM_FEE = 35;

        smartWalletWhitelist = _smartWalletWhitelist;

        redeemEnabled = true;
    }

    // --- modifiers ---

    modifier onlyWhitelistedSmartWallet() {
        if (tx.origin != msg.sender) {
            require(
                address(smartWalletWhitelist) != address(0),
                "Not whitelisted"
            );
            require(
                SmartWalletWhitelist(smartWalletWhitelist).check(msg.sender),
                "Not whitelisted"
            );
        }
        _;
    }

    modifier onlyOwnerOrStrategy() {
        require(msg.sender == owner() || msg.sender == strategy, "Auth failed");
        _;
    }

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || isOperator[msg.sender],
            "Permission denied"
        );
        _;
    }

    // --- Setters ---

    function whitelistOperator(address _operator) external onlyOwner {
        isOperator[_operator] = true;
    }

    function blacklistOperator(address _operator) external onlyOwner {
        isOperator[_operator] = false;
    }

    function initialLock() public {
        require(msg.sender == owner() || msg.sender == address(this), "!auth");

        //create new lock
        uint256 _strategyBalance = IERC20(thena).balanceOf(strategy);
        ILiveTheStrategy(strategy).createLock(_strategyBalance, MAXTIME);

        emit InitialLock(MAXTIME);
    }

    function _increaseAmount(uint256 _amount) internal {
        IERC20(thena).safeTransfer(strategy, _amount);

        uint256 _thenaLocked = ILiveTheStrategy(strategy).balanceOfVeThe();

        if (_thenaLocked > 0) {
            //increase amount
            ILiveTheStrategy(strategy).increaseAmount(_amount);
        } else {
            initialLock();
        }
        emit IncreaseAmount(_amount);
    }

    function setPromotionPeriod(
        bool _isPromotionPeriod,
        uint256 _depositFee
    ) public onlyOwner {
        require(isPromotionPeriod == !_isPromotionPeriod, "Already set");
        isPromotionPeriod = _isPromotionPeriod;
        if (_isPromotionPeriod == true) {
            PROMO_VE_DEPOSIT_FEE = _depositFee;
        }

        emit SetPromotionPeriod(_isPromotionPeriod, _depositFee);
    }

    function setBeginTimestamp(uint256 _timestamp) external onlyOwner {
        beginTimestamp = _timestamp;

        emit SetBeginTimestamp(_timestamp);
    }

    function setThenaPair(address _pair) external onlyOwner {
        require(_pair != address(0), "addr 0");
        thenaPair = _pair;
        emit SetThenaPair(_pair);
    }

    function enableVeTheDeposit() external onlyOwner {
        require(veDepositEnabled == false, "VeThe Depoist is already enabled");
        veDepositEnabled = true;
        emit EnableVeTheDeposit();
    }

    function disableVeTheDeposit() external onlyOwner {
        require(veDepositEnabled == true, "VeThe Depoist is already disabled");
        veDepositEnabled = false;
        emit DisableVeTheDeposit();
    }

    function enableRedeem() public onlyOwnerOrStrategy {
        redeemEnabled = true;
    }

    function disableRedeem() public onlyOwnerOrStrategy {
        redeemEnabled = false;
    }

    function setSupplyPercentageLimit(uint256 _limit) public onlyOwner {
        require(_limit <= MULTIPLIER, "Too large limit");
        supplyPercentageLimit = _limit;
    }

    // --- Main functions ---

    function _deposit(uint256 _amount) internal {
        require(_amount > 0, "!>0");
        IERC20(thena).safeTransferFrom(msg.sender, address(this), _amount);
        _increaseAmount(_amount);
        ILiveThe(liveThe).mint(msg.sender, _amount);

        emit Deposit(msg.sender, _amount);
    }

    //deposit 'underlying' for liVeNFT
    function deposit(
        uint256 _amount
    ) external nonReentrant onlyWhitelistedSmartWallet {
        _deposit(_amount);
    }

    function depositAll() external nonReentrant onlyWhitelistedSmartWallet {
        uint256 _amount = IERC20(thena).balanceOf(msg.sender);
        _deposit(_amount);
    }

    function depositNFT(
        uint256 _tokenId
    ) public nonReentrant onlyWhitelistedSmartWallet {
        require(veDepositEnabled, "NFT Deposit is not enabled");

        uint256 _depositFee;

        if (isPromotionPeriod) {
            _depositFee = PROMO_VE_DEPOSIT_FEE;
        } else {
            require(capAvailableToDeposit(_tokenId), "Cap limited");
            _depositFee = getCurrentDepositFee();
        }

        (int128 _lockedAmount, ) = IVeThe(veThe).locked(_tokenId);
        uint256 _locked = _int128ToUint256(_lockedAmount);

        // uint256 _toMint = IVeThe(veThe).balanceOfNFT(_tokenId)
        //     .mul(MULTIPLIER - _depositFee)
        //     .div(MULTIPLIER);
        uint256 _toMint = _locked.mul(MULTIPLIER - _depositFee).div(MULTIPLIER);

        IVeThe(veThe).transferFrom(msg.sender, strategy, _tokenId);
        ILiveTheStrategy(strategy).merge(_tokenId);

        mintedFromNftAt[getCurrentEpoch()] += _toMint;

        ILiveThe(liveThe).mint(msg.sender, _toMint);

        emit DepositNFT(msg.sender, _tokenId, _toMint);
    }

    function redeem(
        uint256 _amount
    ) external nonReentrant onlyWhitelistedSmartWallet {
        require(redeemEnabled, "Redeem disabled");
        uint256 _toRedeem = _amount.mul(MULTIPLIER - REDEEM_FEE).div(
            MULTIPLIER
        );
        ILiveTheStrategy(strategy).splitAndSend(_toRedeem, msg.sender);
        ILiveThe(liveThe).burn(msg.sender, _amount);

        emit Redeem(msg.sender, _amount, _toRedeem);
    }

    function rebase() external onlyOwnerOrOperator {
        uint _before = ILiveTheStrategy(strategy).balanceOfVeThe();
        ILiveTheStrategy(strategy).claimRebase();
        uint _after = ILiveTheStrategy(strategy).balanceOfVeThe();
        uint _claimed = _after.sub(_before);

        ILiveThe(liveThe).mint(feeManager, _claimed);
        ILiveTheFeeManager(feeManager).distributeRebaseFees(_claimed);
        liveTheSupplyAtCurrentEpoch = ILiveThe(liveThe).totalSupply();

        redeemEnabled = true;

        emit Rebase(_claimed);
    }

    // --- Getters ---

    function capAvailableToDeposit(
        uint256 _tokenId
    ) public view returns (bool isAvailable) {
        uint256 _supplyLimit = liveTheSupplyAtCurrentEpoch
            .mul(supplyPercentageLimit)
            .div(MULTIPLIER);

        (int128 _lockedAmount, ) = IVeThe(veThe).locked(_tokenId);
        uint256 _locked = _int128ToUint256(_lockedAmount);

        uint256 _toMint = _locked.mul(MULTIPLIER - getCurrentDepositFee()).div(
            MULTIPLIER
        );

        if (mintedFromNftAt[getCurrentEpoch()] + _toMint > _supplyLimit)
            return false;

        return true;
    }

    function getCurrentDepositFee() public view returns (uint256) {
        if (isPromotionPeriod) return PROMO_VE_DEPOSIT_FEE;
        uint256 _reserveLiveThe;
        uint256 _reserveThe;

        if (thenaPair == address(0)) return MIN_VE_DEPOSIT_FEE;

        if (liveThe == IThenaPair(thenaPair).token0()) {
            _reserveLiveThe = IThenaPair(thenaPair).reserve0();
            _reserveThe = IThenaPair(thenaPair).reserve1();
        } else if (liveThe == IThenaPair(thenaPair).token1()) {
            _reserveLiveThe = IThenaPair(thenaPair).reserve1();
            _reserveThe = IThenaPair(thenaPair).reserve0();
        }

        uint256 _depositFee;
        if (_reserveLiveThe > 0) {
            _depositFee = _reserveLiveThe.mul(MIN_VE_DEPOSIT_FEE).div(
                _reserveThe
            );
        }

        if (_depositFee < MIN_VE_DEPOSIT_FEE) {
            _depositFee = MIN_VE_DEPOSIT_FEE;
        }
        if (_depositFee > MAX_VE_DEPOSIT_FEE) {
            _depositFee = MAX_VE_DEPOSIT_FEE;
        }

        return _depositFee;
    }

    function getCurrentEpoch() public view returns (uint256 _epoch) {
        _epoch = (block.timestamp - beginTimestamp) / WEEK;
    }

    function _int128ToUint256(int128 _num) internal pure returns (uint256) {
        int256 _num256 = int256(_num);

        if (_num < 0) {
            _num256 = _num256 & int256(type(int128).max);
        }

        uint256 _result = uint256(_num256);
        return _result;
    }

    function withdrawTokens(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
}