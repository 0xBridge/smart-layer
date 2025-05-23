## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

# 0xBridge Smart Layer Contracts

## Contract Documentation

This section provides an overview of the core smart contracts within the 0xBridge system and their roles, particularly focusing on the eBTC minting process.

### Overview of the Minting Flow

1.  **User Action:** A user initiates the process by locking Bitcoin (BTC) in a specific Taproot address controlled by the 0xBridge system (AVS network).
2.  **Off-chain Monitoring:** An off-chain service (Task Generator/Relayer) monitors the Bitcoin blockchain for these locking transactions.
3.  **Task Creation:** Once a valid lock transaction is detected, the Task Generator gathers the necessary details (raw transaction hex, block information, Merkle proof, Taproot address, AVS details) and calls `TaskManager.createNewTask`.
4.  **AVS Verification:** The Actively Validated Service (AVS) network, coordinated via an Attestation Center (not detailed here but interacted with by `TaskManager`), picks up this task. The AVS operators verify:
    - That the relevant Bitcoin block header has been submitted to the `BitcoinLightClient`.
    - That the user's lock transaction is included in that block using the provided Merkle proof and transaction details, verified against the `BitcoinLightClient`.
    - The validity of the transaction details (amount, destination, etc.) parsed from the raw transaction hex.
5.  **Attestation & Confirmation:** Upon successful verification by a quorum of AVS operators, the task is approved, and an attestation is submitted (likely via `AttestationCenter.submitTask`, which then calls `TaskManager.afterTaskSubmission`).
6.  **Cross-Chain Messaging (Home -> Base):** The `TaskManager`, upon receiving confirmation via `afterTaskSubmission`, triggers the `HomeChainCoordinator` to send a message to the `BaseChainCoordinator` on the target EVM chain. This message contains the details needed for minting (user address, amount, original BTC transaction hash).
7.  **eBTC Minting:** The `BaseChainCoordinator` receives the message via its `lzReceive` function, validates it, and calls `eBTCManager.mint` to mint the corresponding amount of `eBTC` tokens to the user's EVM address.

---

### `BitcoinLightClient.sol`

- **Purpose:** Acts as an on-chain verifier for the Bitcoin blockchain on the EVM chain. It allows the system to confirm the existence and validity of Bitcoin blocks and transactions without storing the entire Bitcoin blockchain. It implements Simple Payment Verification (SPV).
- **Key Functions:**
  - `initialize(...)`: Sets up the contract with the initial Bitcoin block (checkpoint) and administrative roles. Uses the UUPS proxy pattern for upgradeability.
  - `submitBlockHeader(...)`, `submitRawBlockHeader(...)`: Allows authorized actors (likely relayers or the AVS) to submit new Bitcoin block headers. It verifies the header's proof-of-work and ensures it connects correctly to a previously known header (either the latest or via intermediate headers).
  - `submitHistoricalBlockHeader(...)`: Similar to `submitBlockHeader` but designed for submitting older blocks, verifying the chain connection downwards from the latest known checkpoint.
  - `verifyHeaderChain(...)`, `verifyHistoricalHeaderChain(...)`: Helper functions to validate the sequence and proof-of-work of a chain of headers.
  - `getBlockHash(...)`: Calculates the Bitcoin block hash from raw header bytes.
  - `getHeader(...)`, `getLatestHeaderHash()`, `getLatestHeader()`: Provide access to stored block header data.
  - `getMerkleRootForBlock(...)`: Returns the Merkle root stored within a validated block header.
  - `verifyTxInclusion(...)`: The core SPV function. Verifies if a given transaction ID (`txId`) is part of a block's validated Merkle root using a provided Merkle proof and transaction index. This is crucial for confirming user lock transactions.
  - `decodeTransactionMetadata(...)`: Parses raw Bitcoin transaction bytes to extract specific metadata, particularly from `OP_RETURN` outputs, which likely contain details like the recipient EVM address, target chain ID, and amounts needed for minting.
  - `_authorizeUpgrade(...)`: Manages contract upgrades (UUPS).

---

### `eBTC.sol`

- **Purpose:** The ERC20 token contract representing Bitcoin on the EVM chain. 1 eBTC is intended to be backed by 1 BTC locked on the Bitcoin network. It's an upgradeable ERC20 token with minting, burning, and permit capabilities.
- **Key Features:**
  - **ERC20 Standard:** Implements standard functions like `transfer`, `approve`, `balanceOf`, etc.
  - **Upgradeable:** Uses UUPS proxy pattern.
  - **Decimals:** Set to 8 to align with Bitcoin's Satoshis.
  - **Access Control:** Uses `AccessControlUpgradeable`. The `MINTER_ROLE` is crucial, controlling who can mint and burn tokens. This role is granted to the `eBTCManager`. The `DEFAULT_ADMIN_ROLE` controls upgrades and role management.
  - **Permit:** Implements EIP-2612 (`ERC20PermitUpgradeable`) for gasless approvals.
- **Key Functions:**
  - `initialize(minter_)`: Sets up the token name, symbol, roles, and permit domain separator.
  - `mint(to, amount)`: Mints new eBTC tokens. Restricted to addresses with `MINTER_ROLE` (i.e., the `eBTCManager`). Called when a BTC lock is confirmed.
  - `burn(amount)`: Burns tokens _from the caller_. Restricted to `MINTER_ROLE`. **Note:** The current implementation restricts `burn` to the `MINTER_ROLE`. This seems unusual for a standard burn mechanism where users typically burn their _own_ tokens. It might be intended that the `eBTCManager` calls this _after_ receiving tokens from a user initiating a withdrawal.
  - `_authorizeUpgrade(...)`: Manages contract upgrades.

---

### `eBTCManager.sol`

- **Purpose:** Manages the core logic for minting and burning `eBTC` tokens. It acts as the bridge between the cross-chain coordination layers (`BaseChainCoordinator`) and the `eBTC` token contract.
- **Key Features:**
  - **Access Control:** Uses `AccessControl` (not upgradeable version). The `DEFAULT_ADMIN_ROLE` manages contract settings, and the `MINTER_ROLE` is granted to the `BaseChainCoordinator` to authorize minting/burning based on verified cross-chain messages.
  - **Pausable:** Allows administrators to pause minting and burning operations.
  - **Reentrancy Guard:** Protects mint/burn functions.
- **Key Functions:**
  - `constructor(initialOwner_)`: Sets up the admin role.
  - `setBaseChainCoordinator(address)`: Grants the `MINTER_ROLE` to the specified `BaseChainCoordinator` address.
  - `setEBTC(address)`: Sets the address of the `eBTC` token contract it manages.
  - `mint(to, amount)`: Mints `eBTC` tokens by calling `_eBTCToken.mint()`. Restricted to `MINTER_ROLE` (called by `BaseChainCoordinator`). Emits `Minted` event.
  - `burn(amount)`: Burns `eBTC` tokens. It first receives tokens from the `msg.sender` (likely the `BaseChainCoordinator` during the burn/unlock flow) and then calls `_eBTCToken.burn()`. Emits `Burn` event. **Note:** This function requires the caller (`BaseChainCoordinator`) to have received the tokens _before_ calling `burn`.
  - `setMinBtcAmount(uint256)`: Sets the minimum threshold for locking/unlocking BTC.
  - `getEBTCTokenAddress()`: Returns the address of the managed `eBTC` token.
  - `pause()`, `unpause()`: Control the paused state of the contract.

---

### `HomeChainCoordinator.sol`

- **Purpose:** Coordinates tasks and messages originating from or related to the "home" chain (where the `BitcoinLightClient` and `TaskManager` likely reside). It interacts with the `BitcoinLightClient` for verification and the `TaskManager` (indirectly via off-chain Task Generator) to initiate verification tasks. It uses LayerZero OApp for cross-chain messaging to the `BaseChainCoordinator`.
- **Key Features:**
  - **LayerZero OApp:** Inherits from `OApp` for sending cross-chain messages.
  - **Interaction with Light Client:** Uses the `_lightClient` to validate Bitcoin blocks and transactions.
  - **PSBT Data Storage:** Stores data related to pending mint/burn operations (`_btcTxnHash_psbtData`), linking Bitcoin transaction hashes to user details, amounts, raw transaction data, and AVS details.
- **Key Functions:**
  - `constructor(...)`: Initializes with addresses for the light client, LayerZero endpoint, owner, and its own chain endpoint ID.
  - `setPeer(...)`: Configures the LayerZero peer address (the `BaseChainCoordinator` on the target chain).
  - `submitBlockAndCreateTask(...)`, `storeMessage(...)`: Entry points for the Task Generator/Relayer to submit Bitcoin block data (to `_lightClient`) and the associated transaction details (`NewTaskParams`) to initiate a mint or prepare for a burn verification. It validates the PSBT data, checks against the light client's Merkle root (currently commented out), and stores the `PSBTData`.
  - `sendMessage(...)`: Triggered (likely by the `TaskManager`'s `afterTaskSubmission` for mints) to send the verified minting details (user, amount, BTC tx hash) to the `BaseChainCoordinator` via LayerZero (`_lzSend`). It updates the status in `_btcTxnHash_psbtData`.
  - `_lzReceive(...)`: Handles incoming LayerZero messages, specifically for initiating the _burn_ process. It receives the raw PSBT data for the _proposed_ burn transaction from the `BaseChainCoordinator`, stores it, and emits `MessageReceived`. This stored data is later used by the Task Generator to create a task for AVS verification of the burn.
  - `getPSBTDataForTxnHash(...)`: Retrieves stored data for a given Bitcoin transaction hash.
  - `updateBurnStatus(...)`: Called by an authorized entity (likely `TaskManager`) after AVS confirms a burn transaction on Bitcoin, marking the burn process as finalized on the EVM side.
  - `getAVSDataForTxnHash(...)`: Returns AVS-specific data (Taproot address, network key, operators) stored for a task.
  - `quote(...)`: Estimates LayerZero messaging fees.
  - `unlockBurntEBTC(...)`: A recovery function to resend a message to `BaseChainCoordinator` if the initial burn-failure handling message failed.

---

### `BaseChainCoordinator.sol`

- **Purpose:** Coordinates tasks and messages on the "base" or target EVM chain where the `eBTC` token and `eBTCManager` reside. It receives messages from the `HomeChainCoordinator` via LayerZero and interacts with the `eBTCManager` to execute minting or handle burn initiation/failures.
- **Key Features:**
  - **LayerZero OApp:** Inherits from `OApp` for receiving cross-chain messages.
  - **Interaction with eBTCManager:** Holds an instance of `_eBTCManagerInstance` to call `mint` and `burn`.
  - **Transaction Tracking:** Stores minimal data (`_btcTxnHash_txnData`) to track processed Bitcoin transactions (for mints) and pending burns initiated by users on this chain.
- **Key Functions:**
  - `constructor(...)`: Initializes with addresses for the LayerZero endpoint, owner, `eBTCManager`, and its own/home chain endpoint IDs.
  - `setPeer(...)`: Configures the LayerZero peer address (the `HomeChainCoordinator`).
  - `setEBTCManager(...)`: Updates the `eBTCManager` address.
  - `lzReceive(...)`: The core message receiving function. It handles two main cases based on the decoded message:
    - **Mint Case:** Receives user address, BTC tx hash, and amount from `HomeChainCoordinator`. Validates uniqueness (`_validateMessageUniqueness`) and inputs, then calls `_eBTCManagerInstance.mint()`. Stores minimal data in `_btcTxnHash_txnData`.
    - **Burn Failure Case:** Receives only the BTC tx hash (specifically, the `keccak256` of the raw proposed burn txn). This indicates the burn process failed on the Bitcoin side or during AVS verification. It retrieves the original user and amount from `_btcTxnHash_txnData` (stored during `burnAndUnlock`), deletes the entry, and _re-mints_ the tokens back to the user (`_handleMinting`).
  - `burnAndUnlockWithPermit(...)`, `burnAndUnlock(...)`: User-facing functions to initiate the eBTC burn process. The user provides the raw _proposed_ (partially signed) Bitcoin transaction (`_rawTxn`) that would unlock their BTC.
    - The contract takes the user's eBTC (via `permit` or `transferFrom`).
    - It approves the `eBTCManager` to spend these tokens.
    - Calls `_burnAndUnlock`.
  - `_burnAndUnlock(...)`: Internal function called by the above.
    - Calculates a _temporary_ hash (`keccak256(_rawTxn)`) to track this specific burn request. Reverts if this request hash already exists.
    - Calls `_eBTCManagerInstance.burn()` to burn the user's tokens (held by this contract).
    - Stores the user and amount in `_btcTxnHash_txnData` against the temporary `keccak256` hash (for potential failure recovery via `lzReceive`).
    - Sends the `_rawTxn` and amount to the `HomeChainCoordinator` via LayerZero (`_lzSend`) to start the AVS verification process for the burn.
  - `getTxnData(...)`: Retrieves stored data for a given Bitcoin transaction hash (or burn request hash).
  - `isMessageProcessed(...)`: Checks if a mint message associated with a BTC tx hash has been processed.

---

### `TaskManager.sol`

- **Purpose:** Acts as the central liaison between the 0xBridge system (specifically the `HomeChainCoordinator`) and the underlying AVS (Attestation Center). It receives task requests initiated off-chain (based on user actions like locking BTC or proposing a burn) and provides hooks for the Attestation Center to call during the task lifecycle.
- **Key Features:**
  - **AVS Agnostic:** Designed to interact with an external Attestation Center contract (`_attestationCenter`).
  - **Task Lifecycle Hooks:** Implements `beforeTaskSubmission` and `afterTaskSubmission` as required by the AVS interface (`IAvsLogic`).
  - **Role-Based Access:** Uses `Ownable` and a specific `_taskCreator` address (likely the off-chain Task Generator/Relayer) authorized to submit new tasks.
- **Key Functions:**
  - `constructor(...)`: Initializes with owner, task creator, Attestation Center, and `HomeChainCoordinator` addresses.
  - `setTaskCreator(...)`: Allows the owner to update the authorized task creator address.
  - `createNewTask(...)`: Called by the `_taskCreator`. It receives all necessary data for AVS verification (block details, tx details, proof, raw transaction, AVS details). It calls `_homeChainCoordinator.storeMessage()` to persist this data and adds the `_btcTxnHash` to its internal list (`_taskHashes`). This function essentially registers the verification request.
  - `beforeTaskSubmission(...)`: Hook called by the `_attestationCenter` _before_ formally accepting a task submission from an operator/aggregator. It performs basic checks: task must be approved, exist (`isTaskExists`), and not already completed (`isTaskCompleted`).
  - `afterTaskSubmission(...)`: Hook called by the `_attestationCenter` _after_ a task has been successfully verified and attested to by the AVS.
    - It decodes the task details (isMint, btcTxnHash, actualTxnHash for burns).
    - Marks the task as completed (`_completedTasks[btcTxnHash] = true`).
    - **Mint Case:** If `isMintTxn` is true, it retrieves the full task data from `HomeChainCoordinator`, quotes the LayerZero fee, and calls `_homeChainCoordinator.sendMessage()` to trigger the minting process on the `BaseChainCoordinator`.
    - **Burn Case:** If `isMintTxn` is false, it calls `_homeChainCoordinator.updateBurnStatus()` with the actual Bitcoin transaction hash (`actualTxnHash`) provided by the AVS, confirming the burn was successful on the Bitcoin side.
  - `isTaskCompleted(...)`, `isTaskExists(...)`: View functions to check the status and existence of tasks based on data in `_completedTasks` and `HomeChainCoordinator`.
  - `getTaskData(...)`: Retrieves task data directly from the `HomeChainCoordinator`.
  - `getTaskHashes(...)`, `getTaskHashesLength()`: Provide access to the list of task hashes created.

<!-- ... rest of README ... -->
