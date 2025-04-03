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

contract Swoupon is BaseHook, ERC20 {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    uint24 public fee = 3000;
    uint24 public constant BASE_FEE = 3000; // 0.03%

    mapping(address => uint256) public freeSwapCount;

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

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        poolManager.updateDynamicLPFee(key, _getFee(hookData)); // this where I need to pull the fee from the deposit
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
    // mints 1 token per swap
        address swapper = abi.decode(hookData, (address));
        _mint(swapper, 1 ether);
        return (BaseHook.afterSwap.selector, 0);
    }
    // checks if swapper has free swaps left
    function _getFee(
        bytes calldata hookData
    ) internal virtual returns (uint24){
        address swapper = abi.decode(hookData, (address));

        if (freeSwapCount[swapper] > 0) {
            freeSwapCount[swapper] -= 1;
            _setFee(0);
        } else {
            _setFee(BASE_FEE);
        }
        return fee;
    }

    function _setFee(uint24 _fee) internal {
        fee = _fee;
    }

    // needs to be able to issue more than 1 token per buy
    function payForFreeSwap(
        uint256 amount
    ) public {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        require(amount >= 1 ether, "Token amount must be 1 or more");
        transfer(address(this), amount);
        freeSwapCount[msg.sender] += 1;
    }

    function getFee() public view returns (uint24) {
        return fee;
    }


}
