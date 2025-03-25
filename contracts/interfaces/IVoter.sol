// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IVoter {
    // Events
    event GaugeCreated(address indexed gauge, address creator, address internal_bribe, address indexed external_bribe, address indexed pool);
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event Voted(address indexed voter, uint256 tokenId, uint256 weight);
    event Abstained(uint256 tokenId, uint256 weight);
    event NotifyReward(address indexed sender, address indexed reward, uint256 amount);
    event DistributeReward(address indexed sender, address indexed gauge, uint256 amount);
    event Whitelisted(address indexed whitelister, address indexed token);
    event Blacklisted(address indexed blacklister, address indexed token);
    event SetMinter(address indexed old, address indexed latest);
    event SetBribeFactory(address indexed old, address indexed latest);
    event SetPairFactory(address indexed old, address indexed latest);
    event SetPermissionRegistry(address indexed old, address indexed latest);
    event SetGaugeFactory(address indexed old, address indexed latest);
    event SetBribeFor(bool isInternal, address indexed old, address indexed latest, address indexed gauge);
    event SetVoteDelay(uint256 old, uint256 latest);
    event AddFactories(address indexed pairfactory, address indexed gaugefactory);

    // State variables
    function _ve() external view returns (address);
    function base() external view returns (address);
    function bribefactory() external view returns (address);
    function minter() external view returns (address);
    function permissionRegistry() external view returns (address);
    function pools(uint256 index) external view returns (address);
    function VOTE_DELAY() external view returns (uint256);
    function claimable(address gauge) external view returns (uint256);
    function gauges(address pool) external view returns (address);
    function gaugesDistributionTimestmap(address gauge) external view returns (uint256);
    function poolForGauge(address gauge) external view returns (address);
    function internal_bribes(address gauge) external view returns (address);
    function external_bribes(address gauge) external view returns (address);
    function votes(uint256 nft, address pool) external view returns (uint256);
    function lastVoted(uint256 nft) external view returns (uint256);
    function isGauge(address gauge) external view returns (bool);
    function isWhitelisted(address token) external view returns (bool);
    function isAlive(address gauge) external view returns (bool);
    function isFactory(address factory) external view returns (bool);
    function isGaugeFactory(address gaugeFactory) external view returns (bool);

    // Admin functions
    function initialize(address __ve, address _pairFactory, address _gaugeFactory, address _bribes) external;
    function _init(address[] calldata _tokens, address _permissionsRegistry, address _minter) external;
    function setVoteDelay(uint256 _delay) external;
    function setMinter(address _minter) external;
    function setBribeFactory(address _bribeFactory) external;
    function setPermissionsRegistry(address _permissionRegistry) external;
    function setNewBribes(address _gauge, address _internal, address _external) external;
    function setInternalBribeFor(address _gauge, address _internal) external;
    function setExternalBribeFor(address _gauge, address _external) external;
    function addFactory(address _pairFactory, address _gaugeFactory) external;
    function replaceFactory(address _pairFactory, address _gaugeFactory, uint256 _pos) external;
    function removeFactory(uint256 _pos) external;

    // Governance functions
    function whitelist(address[] calldata _token) external;
    function blacklist(address[] calldata _token) external;
    function killGauge(address _gauge) external;
    function reviveGauge(address _gauge) external;

    // User functions
    function reset(uint256 _tokenId) external;
    function poke(uint256 _tokenId) external;
    function vote(uint256 _tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external;
    function claimRewards(address[] calldata _gauges) external;
    function claimBribes(address[] calldata _bribes, address[][] calldata _tokens, uint256 _tokenId) external;
    function claimFees(address[] calldata _fees, address[][] calldata _tokens, uint256 _tokenId) external;
    function claimBribes(address[] calldata _bribes, address[][] calldata _tokens) external;
    function claimFees(address[] calldata _bribes, address[][] calldata _tokens) external;

    // Gauge creation
    function createGauges(address[] calldata _pool, uint256[] calldata _gaugeTypes) external returns (address[] memory, address[] memory, address[] memory);
    function createGauge(address _pool, uint256 _gaugeType) external returns (address _gauge, address _internal_bribe, address _external_bribe);

    // View functions
    function length() external view returns (uint256);
    function poolVoteLength(uint256 tokenId) external view returns (uint256);
    function factories() external view returns (address[] memory);
    function factoryLength() external view returns (uint256);
    function gaugeFactories() external view returns (address[] memory);
    function gaugeFactoriesLength() external view returns (uint256);
    function weights(address _pool) external view returns (uint256);
    function weightsAt(address _pool, uint256 _time) external view returns (uint256);
    function totalWeight() external view returns (uint256);
    function totalWeightAt(uint256 _time) external view returns (uint256);
    function _epochTimestamp() external view returns (uint256);

    // Distribution functions
    function notifyRewardAmount(uint256 amount) external;
    function distributeFees(address[] calldata _gauges) external;
    function distributeAll() external;
    function distribute(uint256 start, uint256 finish) external;
    function distribute(address[] calldata _gauges) external;
}