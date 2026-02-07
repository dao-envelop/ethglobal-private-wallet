# Private Wallet - ETHGlobal Hackmoney2026
Backed with Uniswap V4 position
## Deploy Factory And ProxyWallet Implementation
```shell
$ # Deploy in BSC
$ forge script script/DeployFactoryAndWallet.s.sol:DeployFactoryAndWallet --rpc-url bnb_smart_chain  --account env_deploy_2025 --sender 0x13B9cBcB46aD79878af8c9faa835Bee19B977D3D --broadcast --verify --etherscan-api-key $ETHERSCAN_TOKEN

$ # Deploy in Unichain
$ forge script script/DeployFactoryAndWallet.s.sol:DeployFactoryAndWallet --rpc-url unichain  --account env_deploy_2025 --sender 0x13B9cBcB46aD79878af8c9faa835Bee19B977D3D --broadcast --verify --etherscan-api-key $ETHERSCAN_TOKEN 

$ # Run Script for Demo Unstopable transfers from Uniswap V4 position
$  forge script script/InteracteScript_m.s.sol:InteracteScript --rpc-url bnb_smart_chain  --broadcast --via-ir --account secret2
$  forge script script/InteracteScript_m.s.sol:InteracteScript --rpc-url unichain  --broadcast --via-ir --account secret2
```

## Deployment Info (2026-02-07)
#### BSC
**WalletFactory**  
https://bscscan.com/address/0xfcb6910d217AAc4B9d7a205473024964A08Bc8eC#code  

**ProxySmartWallet**  
https://bscscan.com/address/0xa5A1fF40a1F89F26Db124DC56ad6fD8aBb378f29#code

#### Unichain
**WalletFactory**  
https://uniscan.xyz/address/0xBDb5201565925AE934A5622F0E7091aFFceed5EB#code  

**ProxySmartWallet**  
https://uniscan.xyz/address/0x21c23bA0ec49c9440CD259cCB48ff9D06CD16522#code  
 
## Main Concept
```mermaid
sequenceDiagram
  autonumber
  actor Alice as "Alice  (delegated to Calibur)"
  participant PM as "Uniswap v4 Position Manager"
  participant Account as Calibur
  participant F as "Smart Wallet Factory"
  
  

  Note over Alice: "Goal: Alice pays 100 USDT to Bob <br/>while reducing direct address <br/>exposure to Tether blacklist risk."
  alt "Alise has no UniV4 position" 
  Alice->>PM: "Open a liquidity position <br/> (deposit USDT + USDC, mint LP NFT)"
  PM-->>Alice: "LP Position NFT (tokenId)"
  end
  loop send Unstopable Transfer
  Alice->>+Account: execute(BatchedCall batchedCall)
  Account-->>F: "Create Smart Wallet"
  create participant  SW as "Smart Wallet"
  F-->>SW: Deploy Smart Wallet
  F-->>Account: SW address
  Account ->>PM: "Decrease liquidity / collect amounts <br/> from position to Proxy Smart Wallet"
  PM-->>SW: "Receive withdrawn tokens (USDT and/or USDC)"
  Account -->>+SW: "SwapAndTransfer"
  participant V4 as "Uniswap V4 Router"
  SW ->>V4: "Swap (e.g., USDC -> USDT) to unify into USDT"
  V4 -->> SW: "Swaped tokens"
  SW->>Bob: "Transfer 100 USDT"
  SW -->>- Account: "Swapped & Transfered"
  Account-->>-Alice: Transfered
 end

  Note over  Bob: "Observed sender is Proxy Smart Wallet (not Alice EOA)."
  Note over SW: "Proxy can be single-use, and liquidity <br/>path provides operational indirection."
```
