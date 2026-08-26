// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {UniswapV2Pair} from "./UniswapV2Pair.sol";

/// @notice deterministic factory restricted to canonical potential launches.
contract UniswapV2Factory {
    address public owner;
    address public pendingOwner;
    address public pairCreator;
    address public treasury;
    bool public initialized;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 index);
    event PairCreatorUpdated(address indexed previousCreator, address indexed newCreator);
    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error Forbidden();
    error InvalidConfiguration();
    error PairExists();

    constructor() {
        initialized = true;
    }

    function initialize(address owner_, address treasury_) external {
        if (initialized) revert Forbidden();
        if (owner_ == address(0) || treasury_ == address(0) || owner_ == treasury_) {
            revert InvalidConfiguration();
        }
        initialized = true;
        owner = owner_;
        treasury = treasury_;
        emit OwnershipTransferred(address(0), owner_);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function setPairCreator(address newCreator) external {
        if (msg.sender != owner || newCreator == address(0)) revert Forbidden();
        address previous = pairCreator;
        pairCreator = newCreator;
        emit PairCreatorUpdated(previous, newCreator);
    }

    function transferOwnership(address newOwner) external {
        if (msg.sender != owner || newOwner == address(0) || newOwner == treasury) {
            revert Forbidden();
        }
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert Forbidden();
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    function createPair(
        address tokenA,
        address tokenB,
        address quoteToken,
        address activationAuthority,
        address creatorRecipient,
        uint16 lpFeeBps,
        uint16 protocolFeeBps,
        uint16 creatorFeeBps
    ) external returns (address pair) {
        if (msg.sender != pairCreator) revert Forbidden();
        if (tokenA == tokenB) revert InvalidConfiguration();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0) || quoteToken != token0 && quoteToken != token1) {
            revert InvalidConfiguration();
        }
        if (getPair[token0][token1] != address(0)) revert PairExists();
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new UniswapV2Pair{salt: salt}());
        UniswapV2Pair(pair)
            .initialize(
                token0,
                token1,
                quoteToken,
                msg.sender,
                activationAuthority,
                treasury,
                creatorRecipient,
                lpFeeBps,
                protocolFeeBps,
                creatorFeeBps
            );
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
