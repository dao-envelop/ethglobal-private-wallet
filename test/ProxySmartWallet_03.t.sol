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
import {WalletFactory} from "../src/WalletFactory.sol";
import {BaseTest} from "./utils/BaseTest.sol";

import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Commands} from "../src/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";



contract ProxySmartWallet_03Test is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using Address for address;
    uint128 public constant WANT_TO_TRANSFER = 100e6;
    uint128 public constant SLIPPAGE_BPS = 100; // 100 bps - 1%, 10 = 0.1%


    address internal beneficiary = address(0xFEEBEEF);
    
    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    ProxySmartWallet proxyWallet;
    ProxySmartWallet freshProxyWallet;
    WalletFactory factory;
    PoolId poolId;
    IUniversalRouter router;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;


    function setUp() public {
        // Deploys all required artifacts.
        
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();
        factory = new WalletFactory();
        proxyWallet = new ProxySmartWallet(
            address(swapRouter), 
            address(poolManager), 
            address(permit2),
            address(poolManager),
            address(factory)
        );
        
        router = IUniversalRouter(address(swapRouter));

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

        //IERC20(Currency.unwrap(currency0)).approve(address(permit2), type(uint256).max);
        vm.startPrank(address(this));
        permit2.approve(Currency.unwrap(currency0), address(router), type(uint160).max, uint48(block.timestamp + 60));
        permit2.approve(Currency.unwrap(currency1), address(router), type(uint160).max, uint48(block.timestamp + 60));
        vm.stopPrank();

    }


    function test_transferFromWallet() public {

        /////////////////////////////////////////////////
        // Pre conditions: two token balanses should  ///
        // be already at proxy wallet   (tokenId)     ///
        /////////////////////////////////////////////////
        //(PoolKey memory poolKey, PositionInfo info (we not need now))
        (PoolKey memory pK, ) = positionManager.getPoolAndPositionInfo(tokenId);
        pK.currency0.balanceOf(address(this));
        pK.currency1.balanceOf(address(this));

        bytes32 salt = keccak256(abi.encode("User defined nonce", block.timestamp));
        address freshProxyWalletAddress = proxyWallet.predictWalletAddress(salt);

        uint128 liquidityDecrease =  (WANT_TO_TRANSFER + WANT_TO_TRANSFER * SLIPPAGE_BPS / 10000) / 2;
        uint256 amount0Min = liquidityDecrease / 2 - 1e6;
        uint256 amount1Min = liquidityDecrease / 2 - 1e6;
        uint256 amountIn = liquidityDecrease / 2 - 1e6;
        uint256 minAmountOut = 0;
        //address recipient;

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

    // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: pK,
                zeroForOne: true,
                amountIn: uint128(amountIn),
                amountOutMinimum: uint128(minAmountOut),
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(pK.currency0, amountIn);
        params[2] = abi.encode(pK.currency1, minAmountOut);

    // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

    // Execute the swap
    vm.startPrank(address(this));
        router.execute(commands, inputs, block.timestamp + 60);
    vm.stopPrank();

        // bytes memory actions = abi.encodePacked(
        //     uint8(Actions.DECREASE_LIQUIDITY),
        //     uint8(Actions.TAKE_PAIR)
        //     //Actions.SETTLE_PAIR
        // );

        // // // Number of parameters depends on our strategy
        // bytes[] memory params = new bytes[](2);

        // // // Parameters for DECREASE_LIQUIDITY
        // params[0] = abi.encode(
        //     tokenId,              // Position to decrease+
        //     liquidityDecrease,    // Amount to remove
        //     amount0Min,           // Minimum token0 to receive
        //     amount1Min,           // Minimum token1 to receive
        //     Constants.ZERO_BYTES  // No hook data needed
        // );
        
        // // Creating fresh wallet
        // //address freshProxyWalletAddress = factory.createWallet(address(proxyWallet), bytes(""));

        // // !!!!! Should be called from EOA with 7702 delegation !!!!
        // //address freshProxyWalletAddress = proxyWallet.initFreshWallet();
        
        // // Parameters for TAKE_PAIR
        // params[1] = abi.encode(
        //     currency0,
        //     currency1,
        //     freshProxyWalletAddress //recepient
        // );

        // // Which of two  tokens should be transfered
        // Currency curForTransfer = pK.currency1;

        // //address owner = positionManager.ownerOf(tokenId);
        // /////////////////////////////////////////////////////
        // //   Main DEmo Flow could be start from here.      //
        // // Let's suppose that user already have Uni V4     //
        // // position with NFT(tokenId) on her(his) EOA.     // 
        // // The flow is:                                    //
        // // 1. sign 7702 delegation for calibur.            //
        // // 2. Decreae liqudity in position  - get funds    //
        // //    for transfer with target on new proxy wallet //
        // // 3. Swap half of withdrawn assets to one.        //
        // // 4. transfer to beneficiary                      //
        // /////////////////////////////////////////////////////       
        // bytes memory call_01 = abi.encodeCall(
        //     positionManager.modifyLiquidities,
        //     (
        //         abi.encode(actions, params),
        //         block.timestamp + 60 // 60 second deadline
        //     )
        // );
        // console2.logString("Target: Uniswap V4 positionManager");
        // console2.logBytes(call_01);

        // bytes memory call_02 = abi.encodeWithSignature(
        //     "initFreshWallet(bytes32)",
        //     salt
        // );
        // console2.logString("Target: Proxy Wallet implementation");
        // console2.logBytes(call_02);

        // bytes memory call_03 = abi.encodeCall(
        //     freshProxyWallet.swapAndTransfer,
        //     (
        //         pK,
        //         Currency.unwrap(curForTransfer),  //token address for transfer
        //         beneficiary,                      //to
        //         WANT_TO_TRANSFER
        //     )
        // );
        // console2.logString("Target: New Proxy Wallet");
        // console2.logBytes(call_03);

        // vm.startPrank(address(this));
        //   address(positionManager).functionCall(call_01);
        //   address(proxyWallet).functionCall(call_02);
        //   freshProxyWalletAddress.functionCall(call_03);
        // vm.stopPrank();
        // ////////////////////////////////////////////////////////////////////////////////

        
        // assertApproxEqAbs(
        //     curForTransfer.balanceOf(address(beneficiary)), 
        //     WANT_TO_TRANSFER, 
        //     WANT_TO_TRANSFER * SLIPPAGE_BPS / 10_000
        // );
    }
}
