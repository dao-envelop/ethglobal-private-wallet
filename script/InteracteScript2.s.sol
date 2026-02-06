// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Script, console2} from "forge-std/Script.sol";
import "../lib/forge-std/src/StdJson.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ICalibur} from "@uniswap/calibur/interfaces/ICalibur.sol";
import {SignedBatchedCallLib, SignedBatchedCall} from "@uniswap/calibur/libraries/SignedBatchedCallLib.sol";
import {CallLib, Call} from "@uniswap/calibur/libraries/CallLib.sol";
import {BatchedCallLib, BatchedCall} from "@uniswap/calibur/libraries/BatchedCallLib.sol";

contract InteracteScript is Script {
    using stdJson for string;
    using CallLib for Call;
    using BatchedCallLib for BatchedCall;
    using SignedBatchedCallLib for SignedBatchedCall;
    address payable impl_address = payable(0x000000009B1D0aF20D8C6d0A44e162d11F9b8f00);
    address niftsy_address = 0x7728cd70b3dD86210e2bd321437F448231B81733;

    uint256 public immutable forCaliburPK = vm.envUint("FORCALIBUR_PK");
    address payable forCalibur = payable(vm.addr(forCaliburPK));
    uint256 amount = 1;
    address receiver1 = 0xf315B9006C20913D6D8498BDf657E778d4Ddf2c4;
    address receiver2 = 0x5992Fe461F81C8E0aFFA95b831E50e9b3854BA0E;
    address executor = 0x5992Fe461F81C8E0aFFA95b831E50e9b3854BA0E;
    ICalibur public signerAccount;
    bytes constant EMPTY_HOOK_DATA = "";

    function run() public {

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
    }
}
// forge script script/InteracteScript2.s.sol:InteracteScript --rpc-url bnb_smart_chain  --broadcast --via-ir --account secret2
