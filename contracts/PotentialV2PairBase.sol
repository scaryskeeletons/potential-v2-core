// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";

interface IERC20Balance {
    function balanceOf(address account) external view returns (uint256);
}

abstract contract PotentialV2PairBase is UniswapV2ERC20 {
    uint256 public constant MINIMUM_LIQUIDITY = 1_000;
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    address public immutable factory;
    address public token0;
    address public token1;
    address public quoteToken;
    address public launchpad;
    address public activationAuthority;
    address public treasury;
    address public creatorRecipient;

    uint16 public lpFeeBps;
    uint16 public protocolFeeBps;
    uint16 public creatorFeeBps;
    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal blockTimestampLast;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public protocolFees;
    uint256 public creatorFees;
    bool public initialized;
    bool public active;

    uint256 private unlocked = 1;

    event Sync(uint112 reserve0, uint112 reserve1);
    event CreatorRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);

    error Forbidden();
    error Inactive();
    error InvalidConfiguration();
    error Locked();
    error Overflow();
    error TransferFailed();

    modifier lock() {
        if (unlocked != 1) revert Locked();
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor() {
        factory = msg.sender;
    }

    function initialize(
        address token0_,
        address token1_,
        address quoteToken_,
        address launchpad_,
        address activationAuthority_,
        address treasury_,
        address creatorRecipient_,
        uint16 lpFeeBps_,
        uint16 protocolFeeBps_,
        uint16 creatorFeeBps_
    ) external {
        if (msg.sender != factory || initialized) revert Forbidden();
        if (
            token0_ == address(0) || token1_ == address(0) || quoteToken_ != token0_
                && quoteToken_ != token1_ || launchpad_ == address(0)
                || activationAuthority_ == address(0) || treasury_ == address(0)
                || uint256(lpFeeBps_) + protocolFeeBps_ + creatorFeeBps_ > 1_000
                || creatorFeeBps_ != 0 && creatorRecipient_ == address(0)
        ) revert InvalidConfiguration();
        initialized = true;
        token0 = token0_;
        token1 = token1_;
        quoteToken = quoteToken_;
        launchpad = launchpad_;
        activationAuthority = activationAuthority_;
        treasury = treasury_;
        creatorRecipient = creatorRecipient_;
        lpFeeBps = lpFeeBps_;
        protocolFeeBps = protocolFeeBps_;
        creatorFeeBps = creatorFeeBps_;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function setCreatorRecipient(address newRecipient) external {
        if (msg.sender != launchpad || creatorFeeBps == 0 || newRecipient == address(0)) {
            revert Forbidden();
        }
        address previous = creatorRecipient;
        creatorRecipient = newRecipient;
        emit CreatorRecipientUpdated(previous, newRecipient);
    }

    function _principalBalances() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = IERC20Balance(token0).balanceOf(address(this));
        balance1 = IERC20Balance(token1).balanceOf(address(this));
        uint256 liabilities = protocolFees + creatorFees;
        if (quoteToken == token0) balance0 -= liabilities;
        else balance1 -= liabilities;
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();
        uint32 timestamp = uint32(block.timestamp);
        uint32 elapsed;
        unchecked {
            elapsed = timestamp - blockTimestampLast;
        }
        if (elapsed != 0 && reserve0 != 0 && reserve1 != 0) {
            price0CumulativeLast += (uint256(reserve1) << 112) / reserve0 * elapsed;
            price1CumulativeLast += (uint256(reserve0) << 112) / reserve1 * elapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = timestamp;
        emit Sync(reserve0, reserve1);
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, value));
        if (!success || data.length != 0 && !abi.decode(data, (bool))) revert TransferFailed();
    }

    function _requireActive() internal view {
        if (!active) revert Inactive();
    }
}
