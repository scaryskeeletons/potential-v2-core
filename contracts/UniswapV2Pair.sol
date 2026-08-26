// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {PotentialFeeMath} from "./libraries/PotentialFeeMath.sol";
import {PotentialV2Liquidity} from "./PotentialV2Liquidity.sol";

/// @notice exact-input v2 pair with quote-denominated fee liabilities.
contract UniswapV2Pair is PotentialV2Liquidity {
    event Swap(
        address indexed sender,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        uint256 grossQuoteVolume,
        uint256 lpFee,
        uint256 protocolFee,
        uint256 creatorFee,
        address indexed to
    );
    event ProtocolFeesCollected(uint256 amount);
    event CreatorFeesCollected(address indexed recipient, uint256 amount);

    error InsufficientInput();
    error InvalidToken();
    error InvariantViolation();

    function quoteExactInput(address tokenIn, uint256 amountIn)
        public
        view
        returns (uint256 amountOut, uint256 grossQuoteVolume, PotentialFeeMath.Fees memory fees)
    {
        _requireActive();
        if (amountIn == 0) return (0, 0, fees);
        (uint256 reserveIn, uint256 reserveOut) = _orderedReserves(tokenIn);
        if (tokenIn == quoteToken) {
            grossQuoteVolume = amountIn;
            fees = PotentialFeeMath.calculate(amountIn, lpFeeBps, protocolFeeBps, creatorFeeBps);
            amountOut = PotentialFeeMath.amountOut(reserveIn, reserveOut, amountIn - fees.total);
        } else {
            grossQuoteVolume = PotentialFeeMath.amountOut(reserveIn, reserveOut, amountIn);
            fees = PotentialFeeMath.calculate(
                grossQuoteVolume, lpFeeBps, protocolFeeBps, creatorFeeBps
            );
            amountOut = grossQuoteVolume - fees.total;
        }
    }

    function swapExactInput(address tokenIn, address to, uint256 minimumAmountOut)
        external
        lock
        returns (uint256 amountOut, uint256 grossQuoteVolume)
    {
        _requireActive();
        if (to == address(0) || to == token0 || to == token1) revert InvalidRecipient();
        (uint112 old0, uint112 old1,) = getReserves();
        (uint256 principal0, uint256 principal1) = _principalBalances();
        uint256 amountIn;
        if (tokenIn == token0) amountIn = principal0 - old0;
        else if (tokenIn == token1) amountIn = principal1 - old1;
        else revert InvalidToken();
        if (amountIn == 0) revert InsufficientInput();

        PotentialFeeMath.Fees memory fees;
        (amountOut, grossQuoteVolume, fees) = quoteExactInput(tokenIn, amountIn);
        if (amountOut < minimumAmountOut || amountOut == 0) revert InsufficientLiquidity();
        protocolFees += fees.protocol;
        creatorFees += fees.creator;
        address tokenOut = tokenIn == token0 ? token1 : token0;
        _safeTransfer(tokenOut, to, amountOut);

        (principal0, principal1) = _principalBalances();
        if (principal0 * principal1 < uint256(old0) * old1) revert InvariantViolation();
        _update(principal0, principal1);
        emit Swap(
            msg.sender,
            tokenIn,
            amountIn,
            amountOut,
            grossQuoteVolume,
            fees.lp,
            fees.protocol,
            fees.creator,
            to
        );
    }

    function collectProtocolFees() external lock returns (uint256 amount) {
        amount = protocolFees;
        protocolFees = 0;
        if (amount != 0) _safeTransfer(quoteToken, treasury, amount);
        emit ProtocolFeesCollected(amount);
    }

    function collectCreatorFees() external lock returns (uint256 amount) {
        amount = creatorFees;
        creatorFees = 0;
        if (amount != 0) _safeTransfer(quoteToken, creatorRecipient, amount);
        emit CreatorFeesCollected(creatorRecipient, amount);
    }

    function _orderedReserves(address tokenIn) private view returns (uint256, uint256) {
        if (tokenIn == token0) return (reserve0, reserve1);
        if (tokenIn == token1) return (reserve1, reserve0);
        revert InvalidToken();
    }
}
