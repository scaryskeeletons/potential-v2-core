// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

library PotentialFeeMath {
    uint256 internal constant BPS = 10_000;

    struct Fees {
        uint256 total;
        uint256 lp;
        uint256 protocol;
        uint256 creator;
    }

    function calculate(uint256 gross, uint16 lpBps, uint16 protocolBps, uint16 creatorBps)
        internal
        pure
        returns (Fees memory fees)
    {
        uint256 totalBps = uint256(lpBps) + protocolBps + creatorBps;
        fees.total = _ceilDiv(gross * totalBps, BPS);
        fees.protocol = gross * protocolBps / BPS;
        fees.creator = gross * creatorBps / BPS;
        fees.lp = fees.total - fees.protocol - fees.creator;
    }

    function amountOut(uint256 reserveIn, uint256 reserveOut, uint256 amountIn)
        internal
        pure
        returns (uint256)
    {
        return reserveOut * amountIn / (reserveIn + amountIn);
    }

    function _ceilDiv(uint256 value, uint256 denominator) private pure returns (uint256) {
        return value == 0 ? 0 : (value - 1) / denominator + 1;
    }
}
