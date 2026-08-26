// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {Math} from "./libraries/Math.sol";
import {IERC20Balance, PotentialV2PairBase} from "./PotentialV2PairBase.sol";

abstract contract PotentialV2Liquidity is PotentialV2PairBase {
    event Activated(uint256 amount0, uint256 amount1, uint256 liquidity, address indexed sink);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

    error InsufficientLiquidity();
    error InvalidRecipient();

    function sweepBeforeActivation(address tokenSink) external lock {
        if (msg.sender != activationAuthority || active || tokenSink == address(0)) {
            revert Forbidden();
        }
        uint256 balance0 = IERC20Balance(token0).balanceOf(address(this));
        uint256 balance1 = IERC20Balance(token1).balanceOf(address(this));
        if (balance0 != 0) {
            _safeTransfer(token0, token0 == quoteToken ? treasury : tokenSink, balance0);
        }
        if (balance1 != 0) {
            _safeTransfer(token1, token1 == quoteToken ? treasury : tokenSink, balance1);
        }
    }

    function activate(address sink) external lock returns (uint256 liquidity) {
        if (msg.sender != activationAuthority || active || sink == address(0)) revert Forbidden();
        (uint256 balance0, uint256 balance1) = _principalBalances();
        uint256 root = Math.sqrt(balance0 * balance1);
        if (root <= MINIMUM_LIQUIDITY) revert InsufficientLiquidity();
        active = true;
        liquidity = root - MINIMUM_LIQUIDITY;
        _mint(address(0), MINIMUM_LIQUIDITY);
        _mint(sink, liquidity);
        _update(balance0, balance1);
        emit Activated(balance0, balance1, liquidity, sink);
    }

    function mint(address to) external lock returns (uint256 liquidity) {
        _requireActive();
        if (to == address(0)) revert InvalidRecipient();
        (uint112 old0, uint112 old1,) = getReserves();
        (uint256 balance0, uint256 balance1) = _principalBalances();
        uint256 amount0 = balance0 - old0;
        uint256 amount1 = balance1 - old1;
        liquidity = Math.min(amount0 * totalSupply / old0, amount1 * totalSupply / old1);
        if (liquidity == 0) revert InsufficientLiquidity();
        _mint(to, liquidity);
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        _requireActive();
        if (to == address(0) || to == token0 || to == token1) revert InvalidRecipient();
        uint256 liquidity = balanceOf[address(this)];
        (uint256 balance0, uint256 balance1) = _principalBalances();
        amount0 = liquidity * balance0 / totalSupply;
        amount1 = liquidity * balance1 / totalSupply;
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidity();
        _burn(address(this), liquidity);
        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);
        (balance0, balance1) = _principalBalances();
        _update(balance0, balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function skim(address to) external lock {
        _requireActive();
        if (to == address(0)) revert InvalidRecipient();
        (uint256 balance0, uint256 balance1) = _principalBalances();
        if (balance0 > reserve0) _safeTransfer(token0, to, balance0 - reserve0);
        if (balance1 > reserve1) _safeTransfer(token1, to, balance1 - reserve1);
    }

    function sync() external lock {
        _requireActive();
        (uint256 balance0, uint256 balance1) = _principalBalances();
        _update(balance0, balance1);
    }
}
