// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import { Commands } from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Constants } from "@uniswap/v4-core/test/utils/Constants.sol";

import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

// import {Permit2Deployer} from "hookmate/artifacts/Permit2.sol";
// import {V4PoolManagerDeployer} from "hookmate/artifacts/V4PoolManager.sol";
// import {V4PositionManagerDeployer} from "hookmate/artifacts/V4PositionManager.sol";
// import {V4RouterDeployer} from "hookmate/artifacts/V4Router.sol";

interface IFactory {
    function createWallet(address _implementation, bytes memory _initCallData)
        external
        payable
        returns (address wallet);

    function createWallet(address _implementation, bytes memory _initCallData, bytes32 _salt)
        external
        payable
        returns (address wallet); 

    function predictDeterministicAddress(address implementation, bytes32 salt) 
        external 
        view 
        returns (address);   
}


contract ProxySmartWallet {
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;

    IUniswapV4Router04 public immutable router;
    IPoolManager public immutable poolManager;
    IPermit2 public immutable permit2;
    IPositionManager public immutable positionManager;
    IFactory public immutable factory;

    constructor(
    	address _router, 
    	address _poolManager, 
    	address _permit2,
    	address _positionManager,
    	address _factory
    	) {
        router = IUniswapV4Router04(payable(_router));
        poolManager = IPoolManager(_poolManager);
        permit2 = IPermit2(_permit2);
        positionManager = IPositionManager(_positionManager);
        factory = IFactory(_factory);
    }

    function swapAndTransfer(
    	PoolKey memory _poolKey, 
    	address _tokenForTransfer,
    	address _to,
    	uint256 _amount
    ) external 
    {
    	// Prepare swap
    	bool swapDirection;
    	uint256 amountIn; 
    	if  (Currency.unwrap(_poolKey.currency1) == _tokenForTransfer) {
    		swapDirection = true;
    		amountIn = _poolKey.currency0.balanceOf(address(this));
            IERC20(Currency.unwrap(_poolKey.currency0)).approve(address(router), amountIn);
    	} else {
    		amountIn = _poolKey.currency1.balanceOf(address(this));
    		IERC20(Currency.unwrap(_poolKey.currency1)).approve(address(router), amountIn);
    	}
    	router.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: swapDirection,
            poolKey: _poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 60
        });
        uint256 factBalance = IERC20(_tokenForTransfer).balanceOf(address(this)); 
        if (factBalance < _amount ) {
        	_amount = factBalance;
        }
        // Transfer
        IERC20(_tokenForTransfer).safeTransfer(_to, _amount);
    }

    function initFreshWallet() external returns(address freshWallet) {
    	freshWallet = factory.createWallet(address(this), bytes(""));
    }

    function initFreshWallet(bytes32 _salt) external returns(address freshWallet) {
    	freshWallet = factory.createWallet(address(this), bytes(""), _salt);
    }

    function predictWalletAddress(bytes32 _salt) public view returns(address freshWallet) {
    	freshWallet = factory.predictDeterministicAddress(address(this), _salt);
    }
}