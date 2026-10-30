# Independent companion tests

These additions extend the existing suite without changing production contracts or configuration.
All dependencies are already vendored. The tests need no RPC, environment secrets, FFI, or network.

| File | Additional coverage |
| --- | --- |
| `ActivityProperties.t.sol` | Translating round histories and scaling positive work; ageing and waking; floor bounds on block height; maximum cumulative work; invalid checkpoints after RUNNING has already been found; truncated ABI responses; metadata recovery after a dependency outage. |
| `CallbackAtomicity.t.sol` | Different wallets minting in nested callbacks; the last two slots and exhausted nested claims; rollback of forwarded NFTs and nested mints; receiver rejection modes; callback arguments and metadata visibility; restoration of token approvals when safe transfers fail. |
| `LedgerInvariants.t.sol` | Independent ownership, balances, lifetime claims, token approvals, operator approvals, mint blocks, and supply across arbitrary operation sequences. Includes reserve transfers and a campaign beginning with six public slots available. Deterministic sequences guarantee coverage of revocation, self-transfer, operator delegation, rejection rollback, and exhaustion. |

The five discovery passes from the supplied Pashov reference were applied as follows:

| Pass | Property and basis | Exercise |
| --- | --- | --- |
| Conservation | Every NFT belongs to exactly one holder; balances sum to the 99 reserves plus successful public claims. Public claims never exceed 900. Basis: job supply allocation and ERC-721 balance semantics. | A closed set of nine actors with independent ghost balances and owners; fresh and nearly exhausted deployments. |
| Transitions | Claims are permanent; failed calls change no NFT accounting; approvals clear on transfer; mint blocks never change. Basis: lifetime mint limit, static trait, ERC-721 authorization rules. | Successful and rejected mints, transfers, both safe overloads, approvals, revocations, and advancing Ethereum block numbers. |
| Round trips and rounding | Sending a token away and back preserves ownership, supply, balances, claim history and mint block while clearing token approval. Squeek height satisfies floor inequalities and rises by exactly one after one billion more units. | `roundTrip` in the handler and `testFuzzHeightIsFloorAndAddingOneBlockAddsExactlyOne`. |
| Adversarial sequences | Callbacks cannot exceed the cap, leave partial mints on rejection, or transfer reserve tokens without holder authorization. Basis: job mint/reserve requirements and transaction atomicity. | Actual nested calls through `AtomicReceiver`, caught and propagated reverts, full allocation boundaries, and attempted reserve transfers. |
| ERC-721 specifics | A token delegate cannot redelegate; an old owner's operator cannot seize a transferred token; rejected safe transfers restore approvals; callback arguments identify the initiating operator. | Deterministic sequences, random authorization changes, and callback payload fuzzing. |

The ledger predicts effects using ghost state rather than copying contract getters after a call.
Only successful calls update the model. Expected failures assert their exact revert data; an unexpected
success or revert fails the test. At every invariant step it checks aggregate balances, claims,
operator approvals, and all tokens touched so far. `afterInvariant` scans every existing token,
including untouched tokens, after each sequence. No handler skips an operation because it lacks a
token: the initial reserve is always available to select. Public IDs get a dedicated selection branch.

For the nearly exhausted campaign, 894 claims are made through real mint calls, then voluntarily
transferred to the reserve recipient to keep the holder set enumerable. Those transferred public
tokens are additional holdings; the original reserve remains IDs 1–99. Nine actors compete for six
remaining slots, including the reserve recipient and a receiver that can accept or reject NFTs.

The added stateless activity properties run 1,000 cases each. Callback payload fuzzing runs 256 cases.
Each new ledger campaign runs 256 sequences of 64 calls, with unexpected handler reverts treated as
failures. The fixed seed required by the assignment is used for local verification:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x41be4005a735c73b36f76eb18bbb8c20a50e1b78c82d59aa1a02b4ac46d08af2 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

Local result with that seed: build succeeded; 108 tests passed across 11 suites, with no failures
or skips. Each new invariant campaign completed 16,384 handler calls with zero unexpected reverts.
Formatting and the test-only change-scope check passed. The build reports only the two existing
production lint warnings about reserve `_mint` and validation reverts inside the bounded page loop.

Artifact and cache paths are redirected only to keep local generated files within the test workspace.
Plain `forge build` and `forge test` use the same sources and settings. No delivered test imports or
reads `test/scratch`, which may be deleted before verification.

The mocks follow the [published SqueekCore v3 page and tuple semantics](https://docs.squeekchain.com/developers/core/).
Malformed-page and zero-delta-checkpoint cases are defensive input tests, not claims that the live Core
can produce those responses. These tests do not attest to a Sepolia deployment or live proxy state;
the assignment provides no pinned fork block. The supplied protected tests were read as the deployment
floor; their factory environment is not needed by these independent application tests.

No confirmed production defect was found in these checks. This does not establish correctness of
the external Core, its governance, or a future incompatible proxy upgrade.
