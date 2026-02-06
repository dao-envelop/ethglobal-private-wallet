// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Script, console2} from "forge-std/Script.sol";
import "../lib/forge-std/src/StdJson.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ICalibur} from "@uniswap/calibur/interfaces/ICalibur.sol";
import {SignedBatchedCallLib, SignedBatchedCall} from "@uniswap/calibur/libraries/SignedBatchedCallLib.sol";
import {CallLib, Call} from "@uniswap/calibur/libraries/CallLib.sol";
import {BatchedCallLib, BatchedCall} from "@uniswap/calibur/libraries/BatchedCallLib.sol";
import {ProxySmartWallet} from "../src/ProxySmartWallet.sol";
import {WalletFactory} from "../src/WalletFactory.sol";

// Max imports
//import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
//import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
//import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
//import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
//import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
// import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
// import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
// import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "../test/utils/libraries/EasyPosm.sol";

import {ProxySmartWallet} from "../src/ProxySmartWallet.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {BaseTest} from "../test/utils/BaseTest.sol";

import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
// import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
// import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
// import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract InteracteScript is Script, BaseTest {
    using Address for address;
    using stdJson for string;
    using CallLib for Call;
    using BatchedCallLib for BatchedCall;
    using SignedBatchedCallLib for SignedBatchedCall;
    address payable impl_address = payable(0x000000009B1D0aF20D8C6d0A44e162d11F9b8f00);
    address niftsy_address = 0x7728cd70b3dD86210e2bd321437F448231B81733;

    uint256 public immutable forCaliburPK = 0x1111;//vm.envUint("FORCALIBUR_PK");
    address payable forCalibur = payable(vm.addr(forCaliburPK));
    uint256 amount = 1;
    address receiver1 = 0xf315B9006C20913D6D8498BDf657E778d4Ddf2c4;
    address receiver2 = 0x5992Fe461F81C8E0aFFA95b831E50e9b3854BA0E;
    address executor = 0x5992Fe461F81C8E0aFFA95b831E50e9b3854BA0E;
    ICalibur public signerAccount;
    bytes constant EMPTY_HOOK_DATA = "";

    // New /////////////////////////////////////////////////////////////////
    uint256 tokenId; // Uniswap v4 position tokenId
    ProxySmartWallet proxyWallet;
    ProxySmartWallet freshProxyWallet;
    uint128 public constant WANT_TO_TRANSFER = 100e6;
    uint128 public constant SLIPPAGE_BPS = 100; // 100 bps - 1%, 10 = 0.1%
    address internal beneficiary = address(0xFEEBEEF);
    Currency currency0;
    Currency currency1;
    /////////////////////////////////////////////////////////////////////
    function run() public {

        // Get  contracts
        deployArtifactsAndLabel();

        signerAccount = ICalibur(forCalibur);

        Call memory call1;
        Call memory call2;
        Call[] memory _calls = new Call[](2);

        call1.to = niftsy_address;
        call1.value = 0;
        call1.data = abi.encodeWithSelector(ERC20.transfer.selector, receiver1, amount);
        _calls[0] = call1;

        call2.to = address(0);
        call2.value = amount;
        call2.data = "";
        _calls[1] = call2;

        BatchedCall memory batch = BatchedCall({calls: _calls, revertOnFailure: true});

        SignedBatchedCall memory signedCall = SignedBatchedCall({
            batchedCall: batch,
            keyHash: bytes32(0),
            nonce: 2,
            executor: address(0),
            deadline: 0
        });

        bytes32 hash1 = SignedBatchedCallLib.hash(signedCall);
        bytes32 hashToSign = signerAccount.hashTypedData(hash1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(forCaliburPK, hashToSign);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory wrappedSignature = abi.encode(signature, EMPTY_HOOK_DATA);

        vm.startBroadcast(executor);
        signerAccount.execute(signedCall, wrappedSignature);
        vm.stopBroadcast();
        ////////////////////////////////////////////////////////////////////////////////////

        /////////////////////////////////////////////////
        // Pre conditions: two token balanses should  ///
        // be already at proxy wallet   (tokenId)     ///
        /////////////////////////////////////////////////
        //(PoolKey memory poolKey, PositionInfo info (we not need now))
        (PoolKey memory pK, ) = positionManager.getPoolAndPositionInfo(tokenId);
        bytes32 salt = keccak256(abi.encode("User defined nonce", block.timestamp));
        address freshProxyWalletAddress = proxyWallet.predictWalletAddress(salt);

        uint128 liquidityDecrease =  (WANT_TO_TRANSFER + WANT_TO_TRANSFER * SLIPPAGE_BPS / 10000) / 2;
        uint256 amount0Min = liquidityDecrease / 2 - 1e6;
        uint256 amount1Min = liquidityDecrease / 2 - 1e6;
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
            tokenId,              // Position to decrease+
            liquidityDecrease,    // Amount to remove
            amount0Min,           // Minimum token0 to receive
            amount1Min,           // Minimum token1 to receive
            Constants.ZERO_BYTES  // No hook data needed
        );
        
        // Creating fresh wallet
        //address freshProxyWalletAddress = factory.createWallet(address(proxyWallet), bytes(""));

        // !!!!! Should be called from EOA with 7702 delegation !!!!
        //address freshProxyWalletAddress = proxyWallet.initFreshWallet();
        
        // Parameters for TAKE_PAIR
        params[1] = abi.encode(
            pK.currency0,
            pK.currency1,
            freshProxyWalletAddress //recepient
        );

        // Which of two  tokens should be transfered
        Currency curForTransfer = pK.currency1;

        //address owner = positionManager.ownerOf(tokenId);
        /////////////////////////////////////////////////////
        //   Main DEmo Flow could be start from here.      //
        // Let's suppose that user already have Uni V4     //
        // position with NFT(tokenId) on her(his) EOA.     // 
        // The flow is:                                    //
        // 1. sign 7702 delegation for calibur.            //
        // 2. Decreae liqudity in position  - get funds    //
        //    for transfer with target on new proxy wallet //
        // 3. Swap half of withdrawn assets to one.        //
        // 4. transfer to beneficiary                      //
        /////////////////////////////////////////////////////       
        bytes memory call_01 = abi.encodeCall(
            positionManager.modifyLiquidities,
            (
                abi.encode(actions, params),
                block.timestamp + 60 // 60 second deadline
            )
        );
        console2.logString("Target: Uniswap V4 positionManager");
        console2.logBytes(call_01);

        bytes memory call_02 = abi.encodeWithSignature(
            "initFreshWallet(bytes32)",
            salt
        );
        console2.logString("Target: Proxy Wallet implementation");
        console2.logBytes(call_02);

        bytes memory call_03 = abi.encodeCall(
            freshProxyWallet.swapAndTransfer,
            (
                pK,
                Currency.unwrap(curForTransfer),  //token address for transfer
                beneficiary,                      //to
                WANT_TO_TRANSFER
            )
        );
        console2.logString("Target: New Proxy Wallet");
        console2.logBytes(call_03);

        vm.startPrank(address(this));
          address(positionManager).functionCall(call_01);
          address(proxyWallet).functionCall(call_02);
          freshProxyWalletAddress.functionCall(call_03);
        vm.stopPrank();
        ////////////////////////////////////////////////////////////////////////////////
    }
}
// forge script script/InteracteScript2.s.sol:InteracteScript --rpc-url bnb_smart_chain  --broadcast --via-ir --account secret2
