# CAKE Token — Audit Workbench

This repository pins the on-chain source of PancakeSwap's **CAKE** token into a
Foundry project so it can be read, tested, and audited locally.

> ⚠️ **Do not run `forge fmt` on `src/CakeToken.sol`.**
> The file must stay byte-for-byte identical to the verified source on BscScan.
> See [No-formatting policy](#no-formatting-policy) below.

---

## The CAKE Token

- **Network:** BNB Smart Chain (BSC)
- **Address:** [`0x0e09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82`](https://bscscan.com/address/0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82)
- **Compiler:** Solidity `0.6.12`
- **Standard:** BEP-20 (ERC-20-compatible)
- **Name / Symbol / Decimals:** `PancakeSwap Token` / `Cake` / `18`

### What it does

`CakeToken` is a BEP-20 token with two extra capabilities on top of the
standard transfer / approve / allowance surface:

1. **Owner-controlled mint.**
   - `mint(address _to, uint256 _amount)` is `onlyOwner`.
   - On mainnet the owner is the **MasterChef** contract, which mints CAKE as
     farming/staking rewards.
   - There is *no hard cap* — total supply is bounded only by what MasterChef's
     emission schedule produces. This is a property auditors should be
     comfortable with.
   - A separate (unused-by-MasterChef) `mint(uint256)` exists on the parent
     `BEP20` contract and mints to `msg.sender`; also `onlyOwner`.

2. **Compound-style governance checkpoints.**
   - Holders call `delegate(delegatee)` (or `delegateBySig(...)`) to assign
     their voting power.
   - Per-delegate vote balances are recorded as `Checkpoint(fromBlock, votes)`
     in `checkpoints[delegatee][i]`, queryable historically via
     `getPriorVotes(account, blockNumber)`.
   - **Important quirk (preserved on mainnet):** vote balances are moved on
     `mint()` but **not** on `transfer()` / `transferFrom()`. Transferring CAKE
     therefore does *not* update delegated voting weight. The test suite locks
     this property in (`test_transferDoesNotMoveVotes_knownProperty`) so any
     future "fix" surfaces loudly.

### Inheritance

```
Context
  └─ Ownable
       └─ BEP20  ("PancakeSwap Token", "Cake")
            └─ CakeToken          ← adds mint() + governance
```

`SafeMath` and `Address` are bundled as in-file libraries — Solidity 0.6.x has
no built-in overflow checks.

---

## Repository layout

```
src/CakeToken.sol          ← verbatim on-chain source (DO NOT FORMAT)
test/CakeToken.t.sol       ← Foundry test suite (Solidity 0.8.x)
foundry.toml               ← dual-pragma config, fmt exclusion
.github/workflows/test.yml ← CI: build + test (no fmt check)
lib/forge-std              ← Foundry standard library (git submodule)
```

---

## Toolchain & Setup

You need [Foundry](https://book.getfoundry.sh/) installed.

```shell
# Clone with submodules (forge-std)
git clone --recurse-submodules <this-repo>
cd cake-token

# If you already cloned without submodules:
git submodule update --init --recursive

# Build (compiles 0.6.12 for src/, 0.8.x for test/)
forge build

# Run tests
forge test -vv
```

### How the dual Solidity version works

`CakeToken.sol` is pinned to `pragma solidity 0.6.12;` (the exact version of
the verified contract on BscScan). `forge-std` requires `>=0.8.13`. To avoid
touching the on-chain source, the test:

- Stays on `pragma ^0.8.13`.
- Declares an `ICakeToken` interface mirroring the public ABI.
- Deploys the real 0.6.12 contract at runtime via
  `deployCode("CakeToken.sol:CakeToken")`.

`auto_detect_solc = true` in `foundry.toml` lets Foundry pick the matching
compiler per file. EVM version is pinned to **`istanbul`** to match BSC at the
time of CAKE's deployment.

---

## No-formatting policy

**`src/CakeToken.sol` must never be reformatted.**

The point of this repo is to audit the *exact* bytecode-producing source that
lives at `0x0e09...cE82` on BSC. Any whitespace change risks:

- Diverging from the verified BscScan source, making side-by-side review
  harder.
- A different metadata hash, masking a real on-chain difference if anyone ever
  redeploys from this tree.

Enforcement:

- `foundry.toml` excludes `src/CakeToken.sol` from `forge fmt` via
  `fmt = { ignore = ["src/CakeToken.sol"] }`.
- `.github/workflows/test.yml` **does not** run `forge fmt --check`. The step
  that would normally do so has been removed and a comment notes why.
- Reviewers: please reject any PR that touches whitespace, indentation, quote
  style, or trailing commas inside `src/CakeToken.sol`.

If you need to experiment with formatted code, copy it into a scratch file
under `test/` — never edit `src/CakeToken.sol`.

---

## Test coverage (current)

`test/CakeToken.t.sol` exercises:

- Metadata: name / symbol / decimals / totalSupply / owner.
- Ownership: `transferOwnership` happy path and onlyOwner revert.
- Mint: success, non-owner revert, `Transfer(0, to, amount)` event.
- Transfers: success, insufficient balance, transfer-to-zero.
- Allowance: `approve` / `transferFrom`, `increase/decreaseAllowance`.
- Governance:
  - `delegate` records votes and a checkpoint.
  - `mint` moves votes to the existing delegate.
  - Re-delegation shifts votes between delegates.
  - `getPriorVotes` reverts on the current block and returns historical
    snapshots after `vm.roll`.
  - **Locked-in quirk:** `transfer` does NOT move vote weight.

Run a single test:

```shell
forge test --match-test test_delegate_movesVotes -vvvv
```

---

## Useful Foundry commands

```shell
forge build                  # compile
forge test -vv               # run tests
forge test --gas-report      # with gas usage
forge inspect CakeToken abi  # dump ABI
cast call 0x0e09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 \
  "totalSupply()(uint256)" --rpc-url https://bsc-dataseed.binance.org
```

---

## License

The CAKE source code is governed by its original on-chain license. The
scaffolding around it (tests, config, CI) is provided as-is for audit work.
