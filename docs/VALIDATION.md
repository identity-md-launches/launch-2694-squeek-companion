# Local validation and review

This is local implementation evidence, not an independent security audit or a deployment attestation. No transaction was broadcast, no wallet key was used, and no Sepolia collection address or transaction hash is claimed here.

The project builds with Solidity 0.8.26 and the settings in `foundry.toml`. Dependencies are vendored as ordinary files with their upstream licences. `docs/dependencies.json` records the release archive checksums and each vendored file's checksum; OpenZeppelin Contracts v5.4.0 supplies ERC-721, strings and Base64, and forge-std v1.9.7 supplies test utilities. The SqueekCore read interface was checked against the published v3 ABI linked in the README.

Commands used for verification:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x41be4005a735c73b36f76eb18bbb8c20a50e1b78c82d59aa1a02b4ac46d08af2 forge test
forge fmt --check
forge build --sizes
python3 scripts/export_artifacts.py --check
```

Result: `forge build`, `forge test`, `forge fmt --check` and the artifact check passed. Foundry reported **76 tests passed, zero failed and zero skipped**, including its grouped invariant suite, with the requested fuzz seed. All 46 vendored dependency files matched their recorded checksums, and the application artifact had no external library link references.

The suite includes six test contracts and four stateful invariants. Fuzz tests run 512 cases each; the invariant handler runs 128 sequences of depth 64, totaling 8,192 calls. It deliberately mixes successful claims, duplicate claims, legitimate transfers and rejected unauthorized transfers. The handler treats unexpected success or failure as a test failure. The complete cap test successfully claims all 900 public IDs and rejects the next public claim, including a claim from the reserve recipient.

The deployment test uses raw `CREATE2` with the application's creation bytecode, avoiding Foundry's dynamic replacement of Solidity `new` expressions. It removes all Core code and installs a rejecting receiver at the named reserve address first. Construction still succeeds because it has no dependency calls or receiver callbacks; the reserve belongs to the named recipient and the factory has no transfer authority. The deployed runtime also passes the protected floor's reachable-opcode scan for `DELEGATECALL`, `CALLCODE` and `SELFDESTRUCT`.

| Application artifact | Size | Limit |
| --- | ---: | ---: |
| Runtime | 12,193 bytes | 24,576 bytes (EIP-170) |
| Creation bytecode | 13,709 bytes | 49,152 bytes (EIP-3860) |

The raw factory rehearsal costs approximately 7.9 million gas including the test harness's setup and assertions; the constructor itself is approximately 7.2 million gas in the local trace. The launch service must simulate its complete factory transaction and set its gas limit accordingly. The three metadata simulations use approximately 450,000–464,000 gas per `tokenURI` call with the mock Core. These are local estimates, not live Sepolia quotes.

The artifact exporter executes `MetadataTest.testPreviewMetadata` and independently validates the resulting JSON and SVG using Python's standard library. The committed previews use the real renderer, both nested data URIs, numeric height/mint-block attributes and three different backgrounds/expressions. They are not hand-written illustrations of what the contract might return.

The manual review used the supplied security reference to examine access control, receiver callbacks, cumulative arithmetic, loop bounds, dependency behavior and constructor privileges. Findings addressed by the implementation include lifetime eligibility being independent of balances, effects preceding receiver callbacks, rollback for rejected safe mints, exclusive round-window boundaries, cumulative-work deltas, frontier-zero clamping and failing metadata reads when Core is unavailable. Raw ABI words are tested separately from the typed mock so an incorrect simplified tuple would not silently pass both sides of the test.

Two Foundry lint notices are intentional: reserve construction uses `_mint` to avoid external calls to the fixed recipient, and page validation reverts inside a loop bounded by at most 16 records. Neither is suppressed. Public minting uses `_safeMint` and its failure/reentry paths are tested.

Slither and Mythril were not run. The launch's independent review, live dependency check, confirmed transaction/address publication and explorer source verification remain outside these local checks. The most material external assumption is SqueekCore v3 continuing to expose the documented reads at the fixed proxy address. Its reporter/settlement and proxy governance are outside the collection's control.
