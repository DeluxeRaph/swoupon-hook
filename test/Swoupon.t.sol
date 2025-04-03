// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Swoupon} from "../src/Swoupon.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

import {console2} from "forge-std/console2.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
contract SwouponTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Swoupon hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    MockERC20 token0;
	MockERC20 token1;
    address swapper;

    function setUp() public {
        // // creates the pool manager, utility routers, and test tokens
        // deployFreshManagerAndRouters();
        // deployMintAndApprove2Currencies();

        // deployAndApprovePosm(manager);

        // //  // Deploy our TOKEN contract
        // // token = new MockERC20("Test Token", "TEST", 18);
        // // tokenCurrency = Currency.wrap(address(token));

        // // Deploy the hook to an address with the correct flags
        // address flags = address(
        //     uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        // );

        // bytes memory constructorArgs = abi.encode(manager, "Counter", "CTR"); //Add all the necessary constructor arguments from the hook
        // deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
        // hook = Counter(flags);

        // // Create the pool
        // key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        // poolId = key.toId();
        // manager.initialize(key, SQRT_PRICE_1_1);

        // // Provide full-range liquidity to the pool
        // tickLower = TickMath.minUsableTick(key.tickSpacing);
        // tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        // uint128 liquidityAmount = 100e18;

        // (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
        //     SQRT_PRICE_1_1,
        //     TickMath.getSqrtPriceAtTick(tickLower),
        //     TickMath.getSqrtPriceAtTick(tickUpper),
        //     liquidityAmount
        // );

        // (tokenId,) = posm.mint(
        //     key,
        //     tickLower,
        //     tickUpper,
        //     liquidityAmount,
        //     amount0Expected + 1,
        //     amount1Expected + 1,
        //     address(this),
        //     block.timestamp,
        //     ZERO_BYTES
        // );

    deployFreshManagerAndRouters();

    swapper = address(0x123);

    // Deploy our TOKEN contract
    token0 = new MockERC20("Test Token 0", "TEST0", 18);
    token1 = new MockERC20("Test Token 1", "TEST1", 18);
    
    Currency tokenCurrency0 = Currency.wrap(address(token0));
    Currency tokenCurrency1 = Currency.wrap(address(token1));

    // Mint a bunch of TOKEN to ourselves
    token0.mint(swapper, 1000 ether);
    token1.mint(swapper, 1000 ether);

    // Deploy hook to an address that has the proper flags set
    uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

    deployCodeTo(
        "Swoupon.sol",
        abi.encode(manager, "Swoupon", "SWP"),
        address(flags)
    );

        // Deploy our hook
        hook = Swoupon(address(flags));

        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        vm.startPrank(swapper);
        // token0.approve(address(this), type(uint256).max);
        // token1.approve(address(this), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
        vm.stopPrank();

    // Initialize a pool
    (key, ) = initPool(
        tokenCurrency0, // Currency 0 = ETH
        tokenCurrency1, // Currency 1 = TOKEN
        hook, // Hook Contract
        LPFeeLibrary.DYNAMIC_FEE_FLAG, // Swap Fees
        SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
    );
    bytes memory hookData = abi.encode(swapper);
     uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
     uint256 token0ToAdd = 1 ether;

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            token0ToAdd
        );
        vm.startPrank(swapper);
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            hookData
        );
    }

    function test_swap_mint_token_and_pay_for_free_swap() public {
        bytes memory hookData = abi.encode(swapper);

        uint256 tokenBalanceOriginal = hook.balanceOf(swapper);
        uint24 currentFee = hook.getFee();

        assertEq(tokenBalanceOriginal, 0);
        assertEq(currentFee, 3000);
        
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -2 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 tokenBalanceAfterSwap = hook.balanceOf(swapper);
        assertEq(tokenBalanceAfterSwap, 1 ether);

        uint256 tokenBalanceBeforePay = hook.balanceOf(address(hook));
        console.log("tokenBalanceBeforePay", tokenBalanceBeforePay);

        vm.startPrank(swapper);
        hook.payForFreeSwap(1 ether);
        vm.stopPrank();

        //check if use has a free swap left
        assertEq(hook.freeSwapCount(swapper), 1);


        // swapRouter.swap(
        //     key,
        //     IPoolManager.SwapParams({
        //         zeroForOne: true,
        //         amountSpecified: -2 ether, // Exact input for output swap
        //         sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 2
        //     }),
        //     PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
        //     hookData
        // );
        // uint24 feeAfterPay = hook.getFee();
        // assertEq(feeAfterPay, 0);
    }

    


}
