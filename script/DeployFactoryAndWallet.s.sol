// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {Test, console2} from "forge-std/Test.sol";
//import {BaseScript} from "./base/BaseScript.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

import {WalletFactory} from "../src/WalletFactory.sol";
import {ProxySmartWallet} from "../src/ProxySmartWallet.sol";


contract DeployFactoryAndWallet is Script {
	function run() public {
		vm.startBroadcast();
		WalletFactory factory = new WalletFactory();
		ProxySmartWallet walletImpl = new ProxySmartWallet(
            AddressConstants.getV4SwapRouterAddress(block.chainid),
            AddressConstants.getPoolManagerAddress(block.chainid),
            AddressConstants.getPermit2Address(),
            AddressConstants.getPositionManagerAddress(block.chainid),
			address(factory)
		);
		vm.stopBroadcast();

        console2.log("WalletFactory deployed at:", address(factory));
        console2.log("ProxySmartWallet deployed at:", address(walletImpl));

	}

}