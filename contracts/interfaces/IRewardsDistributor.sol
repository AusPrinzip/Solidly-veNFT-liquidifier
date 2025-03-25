// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

interface IRewardsDistributor {
    // Events
    event CheckpointToken(uint time, uint tokens);
    event Claimed(uint tokenId, uint amount, uint claim_epoch, uint max_epoch);

    // View functions
    function start_time() external view returns (uint);
    function time_cursor() external view returns (uint);
    function time_cursor_of(uint tokenId) external view returns (uint);
    function user_epoch_of(uint tokenId) external view returns (uint);
    function last_token_time() external view returns (uint);
    function token_last_balance() external view returns (uint);
    function owner() external view returns (address);
    function voting_escrow() external view returns (address);
    function token() external view returns (address);
    function depositor() external view returns (address);
    function timestamp() external view returns (uint);
    function tokens_per_week(uint week) external view returns (uint);
    function ve_supply(uint timestamp) external view returns (uint);

    // View functions for calculations
    function ve_for_at(uint _tokenId, uint _timestamp) external view returns (uint);
    function claimable(uint _tokenId) external view returns (uint);

    // State-changing functions
    function checkpoint_token() external;
    function checkpoint_total_supply() external;
    function claim(uint _tokenId) external returns (uint);
    function claim_many(uint[] memory _tokenIds) external returns (bool);
    function setDepositor(address _depositor) external;
    function setOwner(address _owner) external;
    function withdrawERC20(address _token) external;
}