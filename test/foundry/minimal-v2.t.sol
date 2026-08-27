// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IFactoryLike {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address feeTo) external;
    function pairCodeHash() external view returns (bytes32);
}

interface IPairLike {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 timestamp);
    function mint(address to) external returns (uint256 liquidity);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function mintProtocolFee() external returns (uint256 liquidity);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function kLast() external view returns (uint256);
}

contract MinimalV2Test is Test {
    uint256 private constant UNIT = 1 ether;
    address private constant TREASURY = address(0x1001);

    IFactoryLike private factory;
    IERC20Like private tokenA;
    IERC20Like private tokenB;
    IPairLike private pair;

    function setUp() external {
        factory = IFactoryLike(
            vm.deployCode("UniswapV2Factory.sol:UniswapV2Factory", abi.encode(address(this)))
        );
        tokenA = IERC20Like(vm.deployCode("ERC20.sol:ERC20", abi.encode(1_000_000 * UNIT)));
        tokenB = IERC20Like(vm.deployCode("ERC20.sol:ERC20", abi.encode(1_000_000 * UNIT)));
        pair = IPairLike(factory.createPair(address(tokenA), address(tokenB)));
        factory.setFeeTo(TREASURY);
        assertTrue(tokenA.transfer(address(pair), 1_000 * UNIT));
        assertTrue(tokenB.transfer(address(pair), 1_000 * UNIT));
        pair.mint(address(0xdead));
    }

    function testSwapChargesFiftyBasisPointsInEitherDirection() external {
        _swap(address(tokenA), UNIT);
        _swap(address(tokenB), UNIT);
    }

    function testFactoryReportsExactPairBytecodeHash() external view {
        assertEq(factory.pairCodeHash(), keccak256(vm.getCode("UniswapV2Pair.sol:UniswapV2Pair")));
    }

    function testProtocolCrystallizationReceivesHalfFeeGrowth() external {
        uint256 kBefore = pair.kLast();
        uint256 supplyBefore = pair.totalSupply();
        _swap(address(tokenA), 10 * UNIT);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 rootK = _sqrt(uint256(reserve0) * reserve1);
        uint256 rootKLast = _sqrt(kBefore);
        uint256 expected = supplyBefore * (rootK - rootKLast) / (rootK + rootKLast);

        uint256 minted = pair.mintProtocolFee();

        assertEq(minted, expected);
        assertEq(pair.balanceOf(TREASURY), expected);
        assertEq(pair.kLast(), uint256(reserve0) * reserve1);
    }

    function testEmptyCrystallizationCannotAdvanceCheckpoint() external {
        uint256 checkpoint = pair.kLast();

        vm.expectRevert(bytes("UniswapV2: NO_PROTOCOL_FEE"));
        pair.mintProtocolFee();

        assertEq(pair.kLast(), checkpoint);
        assertEq(pair.balanceOf(TREASURY), 0);
    }

    function testThirtyBasisPointOutputIsRejected() external {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        bool aIsZero = pair.token0() == address(tokenA);
        uint256 reserveIn = aIsZero ? reserve0 : reserve1;
        uint256 reserveOut = aIsZero ? reserve1 : reserve0;
        uint256 oldFeeOutput = UNIT * 997 * reserveOut / (reserveIn * 1_000 + UNIT * 997);
        assertTrue(tokenA.transfer(address(pair), UNIT));

        vm.expectRevert(bytes("UniswapV2: K"));
        pair.swap(aIsZero ? 0 : oldFeeOutput, aIsZero ? oldFeeOutput : 0, address(this), "");
    }

    function testFiveHundredTwelveAlternatingSwapsPreserveLiquidity() external {
        for (uint256 index; index < 512; ++index) {
            _swap(index % 2 == 0 ? address(tokenA) : address(tokenB), UNIT / 1_000);
        }
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertGt(reserve0, 0);
        assertGt(reserve1, 0);
        assertGt(pair.mintProtocolFee(), 0);
        assertGt(pair.balanceOf(TREASURY), 0);
    }

    function _swap(address tokenIn, uint256 amountIn) private {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        bool zeroForOne = pair.token0() == tokenIn;
        uint256 reserveIn = zeroForOne ? reserve0 : reserve1;
        uint256 reserveOut = zeroForOne ? reserve1 : reserve0;
        uint256 amountInWithFee = amountIn * 9_950;
        uint256 amountOut = amountInWithFee * reserveOut / (reserveIn * 10_000 + amountInWithFee);
        assertTrue(IERC20Like(tokenIn).transfer(address(pair), amountIn));
        pair.swap(zeroForOne ? 0 : amountOut, zeroForOne ? amountOut : 0, address(this), "");
    }

    function _sqrt(uint256 value) private pure returns (uint256 result) {
        if (value == 0) return 0;
        result = value;
        uint256 estimate = value / 2 + 1;
        while (estimate < result) {
            result = estimate;
            estimate = (value / estimate + estimate) / 2;
        }
    }
}
