.PHONY: install test test-foundry test-frontend build build-foundry build-frontend dev deploy-unichain-verified deploy-rsc-verified demo-setup demo-reveal demo-request-settlement demo-claim

install:
	git submodule update --init --recursive
	npm --prefix frontend ci

test: test-foundry test-frontend

test-foundry:
	forge test

test-frontend:
	npm --prefix frontend test

build: build-foundry build-frontend

build-foundry:
	forge build

build-frontend:
	npm --prefix frontend run build

dev:
	npm --prefix frontend run dev

deploy-unichain-verified:
	@test -n "$$UNICHAIN_SEPOLIA_RPC_URL" || (echo "load an exported deployment environment first" && exit 1)
	@test -n "$$ETHERSCAN_API_KEY" || (echo "ETHERSCAN_API_KEY is required" && exit 1)
	forge script script/DeployUnichainDemo.s.sol:DeployUnichainDemo \
		--rpc-url "$$UNICHAIN_SEPOLIA_RPC_URL" --broadcast --slow \
		--verify --verify-external --verifier etherscan \
		--verifier-url "https://api.etherscan.io/v2/api?chainid=1301" \
		--etherscan-api-key "$$ETHERSCAN_API_KEY" -vvvv

deploy-rsc-verified:
	@test -n "$$REACTIVE_LASNA_RPC_URL" || (echo "load an exported deployment environment first" && exit 1)
	@test -n "$$COMMIT_BATCH" || (echo "COMMIT_BATCH is required" && exit 1)
	forge create src/reactive/CommitBatchRSC.sol:CommitBatchRSC \
		--rpc-url "$$REACTIVE_LASNA_RPC_URL" --chain-id 5318007 \
		--private-key "$$PRIVATE_KEY" --broadcast --value "$${RSC_DEPLOYMENT_VALUE:-10000000000000000}" \
		--verify --verifier sourcify -vvvv \
		--constructor-args "$$ORIGIN_CHAIN_ID" "$$DESTINATION_CHAIN_ID" "$$COMMIT_BATCH" "$$COMMIT_BATCH" \
		"$$CALLBACK_GAS_LIMIT" "$$SQRT_PRICE_LIMIT_X96"

demo-setup:
	DEMO_STAGE=setup forge script script/RunDemo.s.sol:RunDemo --rpc-url "$$UNICHAIN_SEPOLIA_RPC_URL" --broadcast --slow -vvvv

demo-reveal:
	DEMO_STAGE=reveal forge script script/RunDemo.s.sol:RunDemo --rpc-url "$$UNICHAIN_SEPOLIA_RPC_URL" --broadcast --slow -vvvv

demo-request-settlement:
	DEMO_STAGE=request-settlement forge script script/RunDemo.s.sol:RunDemo --rpc-url "$$UNICHAIN_SEPOLIA_RPC_URL" --broadcast --slow -vvvv

demo-claim:
	DEMO_STAGE=claim forge script script/RunDemo.s.sol:RunDemo --rpc-url "$$UNICHAIN_SEPOLIA_RPC_URL" --broadcast --slow -vvvv
