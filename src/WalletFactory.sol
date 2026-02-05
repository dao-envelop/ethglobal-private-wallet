// SPDX-License-Identifier: MIT
// ETHGlobal Hackathon.Factory

pragma solidity ^0.8.30;

import "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";



/*
 * @dev https://eips.ethereum.org/EIPS/eip-1167[EIP 1167] is a standard for
 * deploying minimal cheap proxy contracts, also known as "clones".
 */
contract WalletFactory {

    event WalletDeployment(address indexed proxy, address indexed implementation);

    function createWallet(address _implementation, bytes memory _initCallData)
        public
        payable
        returns (address wallet)
    {
        wallet = _clone(_implementation, _initCallData);

        emit WalletDeployment(wallet, _implementation);
    }

    function _clone(address _implementation, bytes memory _initCallData) internal returns (address _contract) {
        _contract = Clones.clone(_implementation);

        // Initialize Wallet
        if (_initCallData.length > 0) {
            Address.functionCallWithValue(_contract, _initCallData, msg.value);
        }
    }
}
