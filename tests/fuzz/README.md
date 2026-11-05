# fuzz

Property-based fuzz tests for zapi's Number, BigInt, and selected binary conversion surfaces. Driven from JS through the `test_fuzz_numeric.node` addon (built by `zig build`) using vitest + fast-check.

See `docs/superpowers/specs/2026-05-28-fuzz-testing-design.md` for design rationale.

## Running

```bash
# Full run (10 000 cases per property)
pnpm test:fuzz:round_trip

# CI-equivalent (1 000 cases per property)
FUZZ_RUNS=1000 pnpm test:fuzz:round_trip

# Single property
pnpm vitest run tests/fuzz/bigint.fuzz.test.ts -t "rtBigIntI128"
```

## When a property fails

fast-check shrinks the counterexample and prints something like:

```
Property failed after 47 tests
Counterexample: 170141183460469231731687303715884105728n
Shrunk 14 times to: 170141183460469231731687303715884105728n
Seed: 1234567890, Path: 0:0:1
```

To reproduce locally, paste the seed into a temporary `it.only`:

```ts
it.only("repro", () => {
    fc.assert(
        fc.property(bigIntArbI128, (b) => ... ),
        { seed: 1234567890, path: "0:0:1", numRuns: 1 },
    );
});
```

Once fixed, **persist the counterexample** so it runs forever:

1. Create or open `tests/fuzz/seeds/<target>.json`.
2. Append the counterexample to the JSON array. For bigints, use:
   ```json
   { "__bigint": "170141183460469231731687303715884105728" }
   ```
   For numbers, use a JSON number directly. For `Uint8Array`, use a JSON array of byte values, e.g. `[0, 255, 1]`. NaN and ±Infinity aren't representable in JSON and are not currently supported as persisted seeds — those values are already in `edgeNumbers` and exercised on every run, so persisting them as regression cases adds nothing. If a future fuzz target needs persisted special-number seeds, extend `loadSeeds` and the relevant `revive*` helper at that time.
3. Commit with the fix.

## Continuous fuzzing (ChainSafe fuzz platform)

`Dockerfile.fuzz` packages these properties for the [fuzz platform](https://github.com/ChainSafe/lodestar-ansible-development/tree/main/playbooks/fuzz). `.github/workflows/fuzz-image.yml` builds and smoke-tests it on PRs and publishes `ghcr.io/chainsafe/zapi-fuzz:main` on every push to `main`; the platform switches the campaign to each new image.

The entrypoint, `tests/fuzz/platform/run-fuzz.ts`, re-runs every `*.fuzz.test.ts` in a loop (`FUZZ_RUNS` cases per property, default 100 000, fresh random seed each time) until `SIGTERM`:

- a failing property is saved once per test + shrunk counterexample to `$FUZZ_FAILURES/failure-<hash>.json` (with seed and path for replay) and logged as `NEW_FAILURE`; fuzzing continues;
- `$FUZZ_METRICS/status` is rewritten after every iteration (`execs_total` counts property cases; no `coverage`/`corpus_entries`, since fast-check is not coverage-guided);
- counters persist in `$FUZZ_STATE/stats.json`;
- a suite that fails to load, or a run with no tests, exits non-zero (an infrastructure failure).

Run it locally as the platform does:

```bash
docker build -f Dockerfile.fuzz -t zapi-fuzz .
mkdir -p /tmp/fz && chmod 777 /tmp/fz
docker run --rm --init --read-only --network none --cap-drop all --user 60001:60001 \
  -e TMPDIR=/fuzz/local -v /tmp/fz:/fuzz zapi-fuzz
```

To reproduce a saved failure, take its `seed` and `path` into the `it.only` shown above.

## Adding a new fuzz target

1. Add the round-trip export to `mod.zig`.
2. Add the oracle to `oracle.test.ts` and run it against every entry in the relevant edge list.
3. Add the fast-check property to the relevant `*.fuzz.test.ts` file.
4. Update `tests/utils/edge.ts` if the target needs new edge values.
5. Run `pnpm test:fuzz:round_trip` and watch it pass (or find a bug).
