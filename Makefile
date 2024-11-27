# Simple Makefile to execute custom commands

include .env

# Variables
SHELL := /bin/bash

# Targets
all: help

# Define a help command to display available commands
help:
	@echo "Available targets:"
	@echo "  deploy  - Deploy the project"
	@echo "  build   - Compiles or builds the project"

# Custom commands
build:
	@echo "Building the project..."
	@echo "Add your build commands here."

deploy:
	@echo "Deploying the project ..."
	@if [ -z "$(SEPOLIA_RPC_URL)" ] || [ -z "$(PRIVATE_KEY)" ]; then \
		echo "Error: SEPOLIA_RPC_URL and PRIVATE_KEY must be set as environment variables."; \
		exit 1; \
	fi
	forge script \
		script/Deployment.s.sol:Deployment \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify -vvvv

