include .env

deploy-testnet:
	forge script script/DeployLendingProtocol.sol --rpc-url $(RSK_TESTNET_RPC_URL) --broadcast --private-key $(PRIVATE_KEY)

deploy-mainnet:
	forge script script/DeployLendingProtocol.sol --rpc-url $(RSK_MAINNET_RPC_URL) --broadcast --private-key $(PRIVATE_KEY)