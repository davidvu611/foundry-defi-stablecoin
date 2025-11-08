## Description
- This is learning project to build a decentralized stablecoin provided by Cyfrin https://github.com/Cyfrin/foundry-defi-stablecoin-cu

- The code work followed Patrict Collins training video: writing smart contract, using chainlink price feed, openzeppelin libraries,etc.
- There project was tested using Foundry platform to perform unit tests, integration test, fuzz test,invariants test...
- A solution to the fast price changing issue was also added :
  + PRICE_CHANGE_PERCENT and PRICE_CHANGE_TIME_FRAME were added to detect the fast price changing (change to often and price change out of setting limit)
  + DSCEngine__PriceChangeTooFrequent(), DSCEngine__PriceChangeExcessLimit() will be raised for such cases

## Requirements
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 1.3.5-stable`

## Quickstart

```
cd foundry-defi-stablecoin
make build
```
# Usage

## Install library and tools
```
make clean install
```

## Build
```
make build
```

## Deploy
Deloy to your local.
```
make deploy
```

## Testing

```
forge test
```

### Test Coverage

```
forge coverage
```

# Deployment to a testnet or mainnet

1. Setup environment variables

- Add environmet varriables to a `.env` file
    RPC_URL=http://localhost:8545
    SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/xxxxxxxxxxxxx
    ETHERSCAN_API_KEY=xxxxxxxxxxxxxxxxxx
    DEFAULT_ANVIL_KEY=0xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    SEPOLIA_PRIVATE_KEY=0xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

- SEPOLIA_RPC_URL: This is url of the sepolia testnet node you're working with.
- ETHERSCAN_API_KEY if you want to verify your contract on [Etherscan](https://etherscan.io/).
- ANVIL_PRIVATE_KEY: private key to deploy the system to Anvil (local Ethereum development node)
- SEPOLIA_PRIVATE_KEY: private key to deploy the system to Seploria test net


2. Get testnet ETH

Head over to https://cloud.google.com/application/web3/faucet/ethereum and get some testnet ETH. You should see the ETH show up in your metamask.

3. Deploy to sepolia testnet

```
make deploy ARGS="--network sepolia"
```

## Estimate gas

You can estimate how much gas things cost by running:

```
forge snapshot
```

And you'll see an output file called `.gas-snapshot`

# Formatting

To run code formatting:

```
forge fmt
```

# Thank Patrick Collins!