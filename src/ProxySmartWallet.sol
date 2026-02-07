// SPDX-License-Identifier: MIT
// ETHGlobal Hackathon
pragma solidity ^0.8.30;

// =========================
// External dependencies
// =========================

// Uniswap v4 core interfaces and types
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// Uniswap v4 periphery
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

// Permit2 (signature-based ERC20 transfers)
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

// ERC20 helpers
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Test / utility constants (used here for ZERO_BYTES)
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

// Hookmate Uniswap v4 router abstraction
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

// =========================
// Wallet factory interface
// =========================

/**
 * @title IFactory
 * @notice Minimal interface for a wallet factory capable of deploying proxy wallets.
 * @dev Supports both CREATE and CREATE2-style deployments.
 */
interface IFactory {
    /**
     * @notice Deploy a new wallet using CREATE.
     * @param _implementation Wallet implementation contract.
     * @param _initCallData Optional initialization calldata.
     */
    function createWallet(address _implementation, bytes memory _initCallData) external payable returns (address wallet);

    /**
     * @notice Deploy a new wallet using CREATE2 with a deterministic salt.
     * @param _implementation Wallet implementation contract.
     * @param _initCallData Optional initialization calldata.
     * @param _salt CREATE2 salt.
     */
    function createWallet(address _implementation, bytes memory _initCallData, bytes32 _salt)
        external
        payable
        returns (address wallet);

    /**
     * @notice Predict deterministic wallet address for a given implementation and salt.
     */
    function predictDeterministicAddress(address implementation, bytes32 salt) external view returns (address);
}

// =========================
// Proxy Smart Wallet
// =========================

/**
 * @title ProxySmartWallet
 * @notice A minimal smart wallet that:
 *         - interacts with Uniswap v4 router for swaps,
 *         - transfers swapped tokens to a beneficiary,
 *         - can deploy new proxy wallets via a factory.
 *
 * @dev Designed to be used as an implementation for proxy wallets.
 *      Each deployed instance can independently hold funds and execute swaps.
 *      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 *      !!!!   Current solution stage is Proof Of Concept for educational purposes ONLY   !!!!!
 *      !!!!   So you have to do your own research  before use in production despite it   !!!!!
 *      !!!!   fully fully work. Please note the unlimited slippage.                      !!!!!
 *      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 */
contract ProxySmartWallet {
    using SafeERC20 for IERC20;

    /// @notice Uniswap v4 router used for swaps
    IUniswapV4Router04 public immutable router;

    /// @notice Uniswap v4 PoolManager (not used directly yet, but stored for extensions)
    IPoolManager public immutable poolManager;

    /// @notice Permit2 contract (not used directly in this contract yet)
    IPermit2 public immutable permit2;

    /// @notice Uniswap v4 PositionManager (for LP positions, unused here for now)
    IPositionManager public immutable positionManager;

    /// @notice Factory used to deploy fresh proxy wallets
    IFactory public immutable factory;

    /**
     * @param _router Address of the Uniswap v4 router
     * @param _poolManager Address of the Uniswap v4 PoolManager
     * @param _permit2 Address of the Permit2 contract
     * @param _positionManager Address of the Uniswap v4 PositionManager
     * @param _factory Address of the wallet factory
     */
    constructor(address _router, address _poolManager, address _permit2, address _positionManager, address _factory) {
        router = IUniswapV4Router04(payable(_router));
        poolManager = IPoolManager(_poolManager);
        permit2 = IPermit2(_permit2);
        positionManager = IPositionManager(_positionManager);
        factory = IFactory(_factory);
    }

    /**
     * @notice Swap all available balance of one pool token into the other
     *         and transfer up to `_amount` of the resulting token to `_to`.
     *
     * @dev
     * - Determines swap direction automatically based on `_tokenForTransfer`
     * - Uses swapExactTokensForTokens with `amountOutMin = 0`
     *   (⚠️ unsafe in production due to unlimited price impact)
     * - Transfers min(actualBalance, _amount) to the recipient
     *
     * @param _poolKey Uniswap v4 pool identifier
     * @param _tokenForTransfer ERC20 token address that should be sent to `_to`
     * @param _to Recipient of the final token transfer
     * @param _amount Desired transfer amount
     */
    function swapAndTransfer(PoolKey memory _poolKey, address _tokenForTransfer, address _to, uint256 _amount)
        external
    {
        require(_to != address(0), "Zero recipient");
        // Determine swap direction and input amount
        bool swapDirection;
        uint256 amountIn;

        // If token1 is the desired output token, swap token0 -> token1
        if (Currency.unwrap(_poolKey.currency1) == _tokenForTransfer) {
            swapDirection = true; // zeroForOne = true
            amountIn = _poolKey.currency0.balanceOf(address(this));
            IERC20(Currency.unwrap(_poolKey.currency0)).approve(address(router), amountIn);
        } else {
            // Otherwise swap token1 -> token0
            amountIn = _poolKey.currency1.balanceOf(address(this));
            IERC20(Currency.unwrap(_poolKey.currency1)).approve(address(router), amountIn);
        }

        // Execute the swap
        router.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // ⚠️ Unsafe: allows unlimited slippage
            zeroForOne: swapDirection,
            poolKey: _poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 60
        });

        // Determine actual received balance
        uint256 factBalance = IERC20(_tokenForTransfer).balanceOf(address(this));

        // Cap transfer amount to available balance
        if (factBalance < _amount) {
            _amount = factBalance;
        }

        // Transfer resulting tokens to recipient
        IERC20(_tokenForTransfer).safeTransfer(_to, _amount);
    }

    /**
     * @notice Deploy a new proxy wallet using CREATE.
     * @return freshWallet Address of the newly deployed wallet
     */
    function initFreshWallet() external returns (address freshWallet) {
        freshWallet = factory.createWallet(address(this), bytes(""));
    }

    /**
     * @notice Deploy a new proxy wallet using CREATE2 with a deterministic salt.
     * @param _salt CREATE2 salt
     * @return freshWallet Address of the newly deployed wallet
     */
    function initFreshWallet(bytes32 _salt) external returns (address freshWallet) {
        freshWallet = factory.createWallet(address(this), bytes(""), _salt);
    }

    /**
     * @notice Predict the address of a proxy wallet deployed via CREATE2.
     * @param _salt CREATE2 salt
     * @return freshWallet Predicted wallet address
     */
    function predictWalletAddress(bytes32 _salt) public view returns (address freshWallet) {
        freshWallet = factory.predictDeterministicAddress(address(this), _salt);
    }
}
