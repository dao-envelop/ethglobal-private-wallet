// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";

import {ProxySmartWallet} from "../src/ProxySmartWallet.sol";
import {BaseTest} from "./utils/BaseTest.sol";

import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
//import {MockERC20} from "@openzeppelin/uniswap-hooks/lib/ solmate/src/test/utils/mocks/MockERC20.sol";
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

//import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
contract ProxySmartWalletTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    uint128 public constant WANT_TO_TRANSFER = 100e6;
    uint128 public constant SLIPPAGE_BPS = 100; // 100 bps - 1%, 10 = 0.1%


    address internal beneficiary = address(0xFEEBEEF);
    
    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    ProxySmartWallet proxyWallet;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        

        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();
        proxyWallet = new ProxySmartWallet(
            address(swapRouter), 
            address(poolManager), 
            address(permit2),
            address(poolManager)
        );

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(0)));
        //poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 10000e6;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function test_proofOfConcept() public {
        assertEq(tokenId, 1);
        assertGt(currency0.balanceOf(address(this)), 0);
        assertGt(currency1.balanceOf(address(this)), 0);
        positionManager.getPoolAndPositionInfo(tokenId);
        //uint128 curL = positionManager.getPositionLiquidity(tokenId);
        uint128 liquidityDecrease =  (WANT_TO_TRANSFER + WANT_TO_TRANSFER * SLIPPAGE_BPS / 10000) / 2;
        uint256 amount0Min = WANT_TO_TRANSFER / 2 - 1e6;
        uint256 amount1Min = WANT_TO_TRANSFER / 2 - 1e6;
        //address recipient;

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
            //Actions.SETTLE_PAIR
        );

        // // Number of parameters depends on our strategy
        bytes[] memory params = new bytes[](2);

        // // Parameters for DECREASE_LIQUIDITY
        params[0] = abi.encode(
            tokenId,           // Position to decrease+
            liquidityDecrease, // Amount to remove
            amount0Min,        // Minimum token0 to receive
            amount1Min,        // Minimum token1 to receive
            Constants.ZERO_BYTES                // No hook data needed
        );

        // Parameters for TAKE_PAIR
        params[1] = abi.encode(
            currency0,
            currency1,
            address(proxyWallet) //recepient
        );

        //address owner = positionManager.ownerOf(tokenId);


        vm.startPrank(address(this));
        //console2.log("Sender is: %s", msg.sender);
        //Execute the decrease
        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60 // 60 second deadline
        );

        vm.stopPrank();

        // Now we should make swap/////////////////////////////////////////////////////////
        // Encode the Universal Router command
        //bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory commands = abi.encodePacked(uint8(0x10));
        bytes[] memory inputs = new bytes[](1);

    // Encode V4Router actions
        actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

    // Prepare parameters for each action
        bytes[] memory params_sw = new bytes[](3);
        params_sw[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountIn: uint128(currency0.balanceOf(address(proxyWallet))),
                amountOutMinimum: uint128(0),//WANT_TO_TRANSFER / 2 - 1e6,
                hookData: bytes("")
            })
        );
        params_sw[1] = abi.encode(currency0, uint128(currency0.balanceOf(address(proxyWallet))));
        params_sw[2] = abi.encode(currency1, uint128(0));

    // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params_sw);

    vm.startPrank(address(proxyWallet));
        IERC20(Currency.unwrap(currency0)).approve(address(permit2), type(uint256).max);
        IERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);

        permit2.approve(Currency.unwrap(currency0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(currency0), address(poolManager), type(uint160).max, type(uint48).max);
        permit2.approve(Currency.unwrap(currency0), address(swapRouter), type(uint160).max, type(uint48).max);
    // Execute the swap
        //IUniversalRouter(address(swapRouter)).execute(commands, inputs, block.timestamp + 60);
        uint256 amountIn = currency0.balanceOf(address(proxyWallet));
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    vm.stopPrank();
    }

    function test_transferFromWallet() public {
        /////////////////////////////////////////////////
        // Pre conditions: two token balanses should  ///
        // be already at proxy wallet                 ///
        /////////////////////////////////////////////////
        uint128 liquidityDecrease =  (WANT_TO_TRANSFER + WANT_TO_TRANSFER * SLIPPAGE_BPS / 10000) / 2;
        uint256 amount0Min = WANT_TO_TRANSFER / 2 - 1e6;
        uint256 amount1Min = WANT_TO_TRANSFER / 2 - 1e6;
        //address recipient;

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
            //Actions.SETTLE_PAIR
        );

        // // Number of parameters depends on our strategy
        bytes[] memory params = new bytes[](2);

        // // Parameters for DECREASE_LIQUIDITY
        params[0] = abi.encode(
            tokenId,           // Position to decrease+
            liquidityDecrease, // Amount to remove
            amount0Min,        // Minimum token0 to receive
            amount1Min,        // Minimum token1 to receive
            Constants.ZERO_BYTES                // No hook data needed
        );

        // Parameters for TAKE_PAIR
        params[1] = abi.encode(
            currency0,
            currency1,
            address(proxyWallet) //recepient
        );

        //address owner = positionManager.ownerOf(tokenId);


        vm.startPrank(address(this));
        //console2.log("Sender is: %s", msg.sender);
        //Execute the decrease
        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60 // 60 second deadline
        );
        vm.stopPrank();
        ///////////////////////////////////////////////// 
        //(PoolKey memory poolKey, PositionInfo info)
        (PoolKey memory pK, ) = positionManager.getPoolAndPositionInfo(tokenId);
        pK.currency0.balanceOf(address(proxyWallet));
        pK.currency1.balanceOf(address(proxyWallet));
        console2.log("proxyWallet.router: %s", address(proxyWallet.router()));
        Currency curForTransfer = pK.currency1; 
        vm.startPrank(address(this));
        proxyWallet.swapAndTransfer(
          pK,
          Currency.unwrap(curForTransfer),  //token address for transfer
          beneficiary,  //to
          WANT_TO_TRANSFER
        );
        vm.stopPrank();
        assertApproxEqAbs(
            curForTransfer.balanceOf(address(beneficiary)), 
            WANT_TO_TRANSFER, 
            WANT_TO_TRANSFER * SLIPPAGE_BPS / 10_000
        );
    }


}
