// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Script, console2} from "forge-std/Script.sol";
import "../lib/forge-std/src/StdJson.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ICalibur} from "@uniswap/calibur/interfaces/ICalibur.sol";
import {SignedBatchedCallLib, SignedBatchedCall} from "@uniswap/calibur/libraries/SignedBatchedCallLib.sol";
import {CallLib, Call} from "@uniswap/calibur/libraries/CallLib.sol";
import {BatchedCallLib, BatchedCall} from "@uniswap/calibur/libraries/BatchedCallLib.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {ProxySmartWallet} from "../src/ProxySmartWallet.sol";
import {BaseTest} from "../test/utils/BaseTest.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract InteracteScript is Script, BaseTest {
    using Address for address;
    using stdJson for string;
    using CallLib for Call;
    using BatchedCallLib for BatchedCall;
    using SignedBatchedCallLib for SignedBatchedCall;
    address niftsy_address = 0x7728cd70b3dD86210e2bd321437F448231B81733;
    address usdt = 0x55d398326f99059fF775485246999027B3197955;
    address usdc = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    uint256 public immutable forCaliburPK = vm.envUint("FORCALIBUR_PK");
    address payable forCalibur = payable(vm.addr(forCaliburPK));
    address executor = 0x5992Fe461F81C8E0aFFA95b831E50e9b3854BA0E;
    ICalibur public signerAccount;
    bytes constant EMPTY_HOOK_DATA = "";
    uint256 nonceForCalibur = 8;  // put new nonce!!!

    uint256 tokenId = 247945; // Uniswap v4 position tokenId
    ProxySmartWallet proxyWallet;
    ProxySmartWallet freshProxyWallet;
    uint128 public constant WANT_TO_TRANSFER = 1e16;
    uint128 public constant SLIPPAGE_BPS = 100; // 100 bps - 1%, 10 = 0.1%
    address internal beneficiary = address(0x5992Fe461F81C8E0aFFA95b831E50e9b3854BA0E);
    Currency currency0;
    Currency currency1;
    /////////////////////////////////////////////////////////////////////
    function run() public {
        deployArtifactsAndLabel();

        currency0 = Currency.wrap(usdt);
        currency1 = Currency.wrap(usdc);

        // Get  contracts
        proxyWallet = ProxySmartWallet(0x8a3e1e1680cF2279D9eCa6E55e4E8897363Ea60d);
        /////
        
        ////////////////////////////////////////////////////////////////////////////////////

        /////////////////////////////////////////////////
        // Pre conditions: two token balanses should  ///
        // be already at proxy wallet   (tokenId)     ///
        /////////////////////////////////////////////////
        //(PoolKey memory poolKey, PositionInfo info (we not need now))
        
        bytes32 salt = keccak256(abi.encode("User defined nonce", block.timestamp));
        address freshProxyWalletAddress = proxyWallet.predictWalletAddress(salt);
        (PoolKey memory pK, ) = positionManager.getPoolAndPositionInfo(tokenId);

        uint128 liquidityDecrease =  (WANT_TO_TRANSFER + WANT_TO_TRANSFER * SLIPPAGE_BPS / 10000) / 2;
        uint256 amount0Min = liquidityDecrease / 2 - 1e10;
        uint256 amount1Min = liquidityDecrease / 2 - 1e10;

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
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

        bytes memory call_01 = abi.encodeWithSignature(
            "initFreshWallet(bytes32)",
            salt
        );
        console2.logString("Target: Proxy Wallet implementation");
        console2.logBytes(call_01);

        bytes memory call_02 = abi.encodeCall(
            positionManager.modifyLiquidities,
            (
                abi.encode(actions, params),
                block.timestamp + 60 // 60 second deadline
            )
        );
        console2.logString("Target: Uniswap V4 positionManager");
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

        // Calibur part //
        signerAccount = ICalibur(forCalibur);

        Call memory call1;
        Call memory call2;
        Call memory call3;
        Call[] memory _calls = new Call[](3);

        call1.to = address(proxyWallet);
        call1.value = 0;
        call1.data = call_01;
        _calls[0] = call1;

        call2.to = address(positionManager);
        call2.value = 0;
        call2.data = call_02;
        _calls[1] = call2;

        call3.to = freshProxyWalletAddress;
        call3.value = 0;
        call3.data = call_03;
        _calls[2] = call3;

        BatchedCall memory batch = BatchedCall({calls: _calls, revertOnFailure: true});

        SignedBatchedCall memory signedCall = SignedBatchedCall({
            batchedCall: batch,
            keyHash: bytes32(0),
            nonce: nonceForCalibur,
            executor: address(0),
            deadline: 0
        });

        bytes32 preparedHash = SignedBatchedCallLib.hash(signedCall);
        bytes32 hashToSign = signerAccount.hashTypedData(preparedHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(forCaliburPK, hashToSign);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory wrappedSignature = abi.encode(signature, EMPTY_HOOK_DATA);

        vm.startBroadcast(executor);
        signerAccount.execute(signedCall, wrappedSignature);
        vm.stopBroadcast();
        ////////////////////////////////////////////////////////////////////////////////
    }
}
// forge script script/InteracteScript_m.s.sol:InteracteScript --rpc-url bnb_smart_chain  --broadcast --via-ir --account secret2
