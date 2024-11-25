# Simple Makefile to execute custom commands

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
	@echo "Loading Environment variables ..."
	source .env
	@echo "Deploying ..."
	forge script --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv script/Deployment.s.sol:Deployment

