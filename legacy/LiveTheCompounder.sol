// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "./interfaces/ILiveTheChef.sol";
import "./interfaces/ISmartWalletWhitelist.sol";

contract LiveTheCompounder is
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    IERC20Upgradeable public token;
    ILiveTheChef public liveTheChef;
    address public smartWalletChecker;
    string public __NAME__;
    uint256 public performanceFee;
    address public treasury;

    constructor() public {}

    function initialize(
        string memory _name,
        address _liveThe,
        address _liveTheChef,
        address _smartWalletChecker
    ) public initializer {
        __ERC20_init("sliveThe", "sliveThe");
        __Ownable_init();
        __ReentrancyGuard_init();
        token = IERC20Upgradeable(_liveThe);
        liveTheChef = ILiveTheChef(_liveTheChef);
        __NAME__ = _name;
        smartWalletChecker = _smartWalletChecker;
    }

    modifier onlyWhitelisted() {
        if (tx.origin != msg.sender) {
            require(
                address(smartWalletChecker) != address(0),
                "Not whitelisted"
            );
            require(
                ISmartWalletWhitelist(smartWalletChecker).check(msg.sender),
                "Not whitelisted"
            );
        }
        _;
    }

    function balanceNotInPool() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256 _balance) {
        (_balance, ) = liveTheChef.userInfo(address(this));
    }

    function balance() public view returns (uint256 _balance) {
        _balance = balanceNotInPool().add(balanceOfPool());
    }

    function deposit(uint256 _amount) public onlyWhitelisted nonReentrant {
        uint256 _pool = balance();
        uint256 _shares = 0;
        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, _shares);
        token.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function earn() public nonReentrant {
        require(
            ISmartWalletWhitelist(smartWalletChecker).check(msg.sender),
            "Not whitelisted"
        );

        uint256 _balanceBefore = balanceNotInPool();
        liveTheChef.harvest(address(this));
        uint256 _balance = balanceNotInPool();
        uint256 _amount = _balance.sub(_balanceBefore);
        uint256 _feeAmount = _amount.mul(performanceFee).div(10000);
        token.safeTransfer(treasury, _feeAmount);
        uint256 _newBalance = _balance.sub(_feeAmount);
        token.safeApprove(address(liveTheChef), 0);
        token.safeApprove(address(liveTheChef), _newBalance);
        liveTheChef.deposit(_newBalance, address(this));
    }

    function setPerformanceFee(uint256 _fee) external onlyOwner {
        performanceFee = _fee;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) public onlyWhitelisted nonReentrant {
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        uint256 _balance = balanceNotInPool();
        if (r > _balance) {
            uint256 _amount = r.sub(_balance);
            liveTheChef.withdraw(_amount, address(this));
        }
        _burn(msg.sender, _shares);

        token.safeTransfer(msg.sender, r);
    }

    function getRatio() public view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return balance().mul(1e18).div(totalSupply());
    }
}