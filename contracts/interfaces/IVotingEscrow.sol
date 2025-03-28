// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721, IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title Voting Escrow Interface
/// @notice Interface for veNFT implementation that escrows ERC-20 tokens in the form of an ERC-721 NFT
interface IVotingEscrow is IERC721, IERC721Metadata, IVotes {
    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME,
        MERGE_TYPE,
        SPLIT_TYPE
    }

    struct LockedBalance {
        int128 amount;
        uint end;
    }

    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint ts;
        uint blk; // block
    }

    /// @notice A checkpoint for marking delegated tokenIds from a given timestamp
    struct Checkpoint {
        uint timestamp;
        uint[] tokenIds;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(
        address indexed provider,
        uint tokenId,
        uint value,
        uint indexed locktime,
        DepositType deposit_type,
        uint ts
    );
    event Withdraw(address indexed provider, uint tokenId, uint value, uint ts);
    event Supply(uint prevSupply, uint supply);

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function locked(uint id) external view returns(LockedBalance memory);
    function token() external view returns (address);
    function voter() external view returns (address);
    function team() external view returns (address);
    function artProxy() external view returns (address);
    function point_history(uint epoch) external view returns (Point memory);
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function version() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function tokenURI(uint _tokenId) external view returns (string memory);
    function ownerOf(uint _tokenId) external view returns (address);
    function balanceOf(address _owner) external view returns (uint);
    function getApproved(uint _tokenId) external view returns (address);
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
    function isApprovedOrOwner(address _spender, uint _tokenId) external view returns (bool);
    function block_number() external view returns (uint);
    function get_last_user_slope(uint _tokenId) external view returns (int128);
    function user_point_history__ts(uint _tokenId, uint _idx) external view returns (uint);
    function locked__end(uint _tokenId) external view returns (uint);
    function tokenOfOwnerByIndex(address _owner, uint _tokenIndex) external view returns (uint);
    function balanceOfNFT(uint _tokenId) external view returns (uint);
    function balanceOfNFTAt(uint _tokenId, uint _t) external view returns (uint);
    function balanceOfAtNFT(uint _tokenId, uint _block) external view returns (uint);
    function totalSupplyAt(uint _block) external view returns (uint);
    function totalSupply() external view returns (uint);
    function totalSupplyAtT(uint t) external view returns (uint);
    function attachments(uint _tokenId) external view returns (uint);
    function voted(uint _tokenId) external view returns (bool);
    function ownership_change(uint _tokenId) external view returns (uint);
    function delegates(address delegator) external view returns (address);
    function getVotes(address account) external view returns (uint);
    function getPastVotesIndex(address account, uint timestamp) external view returns (uint32);
    function getPastVotes(address account, uint timestamp) external view returns (uint);
    function getPastTotalSupply(uint256 timestamp) external view returns (uint);
    function checkpoints(address account, uint32 index) external view returns (Checkpoint memory);
    function numCheckpoints(address account) external view returns (uint32);
    function nonces(address account) external view returns (uint);
    function DOMAIN_TYPEHASH() external pure returns (bytes32);
    function DELEGATION_TYPEHASH() external pure returns (bytes32);
    function MAX_DELEGATES() external pure returns (uint);
    function supportsInterface(bytes4 _interfaceID) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                           MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setTeam(address _team) external;
    function setArtProxy(address _proxy) external;
    function approve(address _approved, uint _tokenId) external;
    function setApprovalForAll(address _operator, bool _approved) external;
    function transferFrom(address _from, address _to, uint _tokenId) external;
    function safeTransferFrom(address _from, address _to, uint _tokenId) external;
    function safeTransferFrom(address _from, address _to, uint _tokenId, bytes memory _data) external;
    function checkpoint() external;
    function deposit_for(uint _tokenId, uint _value) external;
    function create_lock(uint _value, uint _lock_duration) external returns (uint);
    function create_lock_for(uint _value, uint _lock_duration, address _to) external returns (uint);
    function increase_amount(uint _tokenId, uint _value) external;
    function increase_unlock_time(uint _tokenId, uint _lock_duration) external;
    function withdraw(uint _tokenId) external;
    function setVoter(address _voter) external;
    function voting(uint _tokenId) external;
    function abstain(uint _tokenId) external;
    function attach(uint _tokenId) external;
    function detach(uint _tokenId) external;
    function merge(uint _from, uint _to) external;
    function split(uint[] memory amounts, uint _tokenId) external;
    function delegate(address delegatee) external;
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) external;
}