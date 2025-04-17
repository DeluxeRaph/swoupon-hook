// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {IMsgSender} from "./interfaces/IMsgSender.sol";
//Welcome to Swoupon.
//after 10 swaps earn a feeless swap.

contract Swoupon is BaseHook, ERC20 {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    uint24 public fee = 3000;
    uint24 public constant BASE_FEE = 10000; // 0.1%

    address swapper = address(0);

    mapping(address => uint256) public redeemCount;
    mapping(address => bool) public verifiedRouters;

    error NotDynamicFee();

    constructor(IPoolManager _poolManager, string memory _name, string memory _symbol)
        BaseHook(_poolManager)
        ERC20(_name, _symbol, 18)
    {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _afterInitialize(address, PoolKey calldata key, uint160, int24)
        internal
        virtual
        override
        returns (bytes4)
    {
        if (!key.fee.isDynamicFee()) revert NotDynamicFee();
        return this.afterInitialize.selector;
    }

    function _beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // @note does router safe from reentrancy on the msgSender?
        // if sender is verified router, set swapper to the msgSender
        if (verifiedRouters[sender]) {
            swapper = IMsgSender(sender).msgSender();
        }

        fee = _getFee();
        poolManager.updateDynamicLPFee(key, fee); // this where I need to pull the fee from the deposit
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee);
    }

    function _afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        // mints 1 token per swap
        if (swapper == address(0)) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // check if fee is 0 and if so don't mint
        if (fee == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }
        
        _mint(swapper, 1 ether);
        return (BaseHook.afterSwap.selector, 0);
        
    }

    // Checks if swapper has a free swap left and sets the fee accordingly
    function _getFee() internal virtual returns (uint24) {
        if (redeemCount[swapper] > 0) {
            redeemCount[swapper] -= 1;
            _setFee(0);
        } else {
            _setFee(BASE_FEE);
        }
        return fee;
    }

    // Swapper pays n swoupon tokens to get 1 feeless swap.
    function redeemSwap(uint256 amount) public {
        require(balanceOf[swapper] >= amount, "Insufficient balance");
        require(amount >= 1 ether, "Token amount must be 1 or more");
        
        transfer(address(this), amount);
        redeemCount[swapper] += amount;
    }

    function getFee() public view returns (uint24) {
        return fee;
    }

    function _setFee(uint24 _fee) internal {
        fee = _fee;
    }

    ///////////////////////
    ///// Router Stuff/////
    ///////////////////////

    /// @notice Add a router to the trusted list
    function addRouter(address _router) external {
        verifiedRouters[_router] = true;
    }

    /// @notice Remove a router from the trusted list
    function removeRouter(address _router) external {
        verifiedRouters[_router] = false;
    }

    /// @notice View if a router is verified
    function isVerifiedRouter(address _router) external view returns (bool) {
        return verifiedRouters[_router];
    }
}
