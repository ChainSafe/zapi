// Entrypoint of the zapi fuzz image (Dockerfile.fuzz) on the ChainSafe fuzz platform.
//
// Re-runs the fast-check properties (tests/fuzz/*.fuzz.test.ts) in a loop, each
// iteration with a fresh random seed, and fulfils the platform's container contract:
//   - runs until SIGTERM; any other exit is a failure
//   - a property failure is a finding, not a crash of this process: it is saved,
//     deduplicated by test name + shrunk counterexample, to $FUZZ_FAILURES and
//     announced with a NEW_FAILURE line
//   - $FUZZ_METRICS/status is rewritten after every iteration (seconds apart)
//   - cumulative counters live in $FUZZ_STATE, so they survive restarts
//   - an infrastructure failure (addon fails to load, no tests ran) exits non-zero
//
// fast-check is not coverage-guided, so there is no corpus: `coverage` and
// `corpus_entries` are not reported, and `execs_total` counts property cases.
import {spawn} from "node:child_process";
import {createHash} from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";

const env = (name: string, fallback: string): string => process.env[name] || fallback;

const ROOT = path.resolve(import.meta.dirname, "../../..");
const STATE = env("FUZZ_STATE", "/fuzz/state");
const FAILURES = env("FUZZ_FAILURES", "/fuzz/failures");
const METRICS = env("FUZZ_METRICS", "/fuzz/metrics");
const TMP = env("TMPDIR", "/tmp");
// Cases per property per iteration. Keep an iteration well under a minute: the
// status file is the platform's liveness signal and is written between iterations.
const RUNS = Number(env("FUZZ_RUNS", "100000"));
const STATS_FILE = path.join(STATE, "stats.json");
const REPORT_FILE = path.join(TMP, "vitest-report.json");

type Stats = {execsTotal: number; iterations: number; lastFindTimestamp: number};
type AssertionResult = {fullName: string; status: string; failureMessages: string[]};
type Report = {
  numTotalTests: number;
  numFailedTests: number;
  testResults: {name: string; message?: string; assertionResults: AssertionResult[]}[];
};

for (const dir of [STATE, FAILURES, METRICS, TMP]) fs.mkdirSync(dir, {recursive: true});

function writeAtomic(file: string, content: string): void {
  fs.writeFileSync(`${file}.tmp`, content);
  fs.renameSync(`${file}.tmp`, file);
}

function loadStats(): Stats {
  try {
    return JSON.parse(fs.readFileSync(STATS_FILE, "utf8")) as Stats;
  } catch {
    return {execsTotal: 0, iterations: 0, lastFindTimestamp: 0};
  }
}

const stats = loadStats();
let execsPerSecond = 0;

function writeStatus(): void {
  const crashes = fs.readdirSync(FAILURES).filter((f) => f.startsWith("failure-")).length;
  const lines = [
    `execs_total ${stats.execsTotal}`,
    `execs_per_second ${execsPerSecond.toFixed(1)}`,
    `crashes_total ${crashes}`,
    "hangs_total 0",
  ];
  if (stats.lastFindTimestamp > 0) lines.push(`last_find_timestamp_seconds ${stats.lastFindTimestamp}`);
  writeAtomic(path.join(METRICS, "status"), `${lines.join("\n")}\n`);
  writeAtomic(STATS_FILE, JSON.stringify(stats));
}

function saveFailure(test: AssertionResult): void {
  const message = test.failureMessages.join("\n");
  // The seed differs every iteration; the shrunk counterexample does not.
  const counterexample = /Counterexample: (.*)/.exec(message)?.[1] ?? message.split("\n")[0];
  const id = createHash("sha256").update(`${test.fullName}\0${counterexample}`).digest("hex").slice(0, 16);
  const file = path.join(FAILURES, `failure-${id}.json`);
  if (fs.existsSync(file)) return;
  const seed = /seed: (-?\d+), path: "([^"]*)"/.exec(message);
  const record = {
    counterexample,
    message,
    path: seed?.[2] ?? null,
    revision: env("FUZZ_REVISION", "unknown"),
    seed: seed ? Number(seed[1]) : null,
    test: test.fullName,
    timestamp: new Date().toISOString(),
  };
  writeAtomic(file, `${JSON.stringify(record, null, 2)}\n`);
  stats.lastFindTimestamp = Math.floor(Date.now() / 1000);
  console.log(`NEW_FAILURE file=failure-${id}.json test="${test.fullName}" counterexample=${counterexample}`);
}

function fatal(reason: string, output: string): never {
  console.log(`FATAL ${reason}; last output:\n${output.split("\n").slice(-30).join("\n")}`);
  writeStatus();
  process.exit(1);
}

let stopping = false;
let child: ReturnType<typeof spawn> | undefined;
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => {
    console.log(`${signal}: stopping`);
    stopping = true;
    child?.kill("SIGTERM");
  });
}

function runIteration(): Promise<{code: number | null; output: string}> {
  fs.rmSync(REPORT_FILE, {force: true});
  return new Promise((resolve) => {
    child = spawn(
      process.execPath,
      [
        path.join(ROOT, "node_modules/vitest/vitest.mjs"),
        "run",
        ".fuzz.test.ts",
        "--reporter=json",
        `--outputFile=${REPORT_FILE}`,
      ],
      {cwd: ROOT, env: {...process.env, FUZZ_RUNS: String(RUNS)}, stdio: ["ignore", "pipe", "pipe"]}
    );
    let output = "";
    const collect = (chunk: Buffer): void => {
      output = (output + chunk.toString()).slice(-64 * 1024);
    };
    child.stdout?.on("data", collect);
    child.stderr?.on("data", collect);
    child.on("close", (code) => resolve({code, output}));
  });
}

console.log(
  `START project=${env("FUZZ_PROJECT", "zapi")} target=${env("FUZZ_TARGET", "round-trip")} runs=${RUNS} resumed_execs=${stats.execsTotal}`
);
writeStatus();

while (!stopping) {
  const started = Date.now();
  const {code, output} = await runIteration();
  if (stopping) break;

  let report: Report;
  try {
    report = JSON.parse(fs.readFileSync(REPORT_FILE, "utf8")) as Report;
  } catch {
    fatal(`vitest exited ${code} without a report`, output);
  }
  // A suite that fails to load (e.g. the addon is missing) has a message but no tests.
  const suiteErrors = report.testResults
    .filter((f) => f.message)
    .map((f) => `${f.name}: ${f.message}`)
    .join("\n");
  if (suiteErrors) fatal("a test suite failed to load", suiteErrors);
  if (report.numTotalTests === 0) fatal("vitest ran no tests", output);
  if (code !== 0 && report.numFailedTests === 0) fatal(`vitest exited ${code} with no failed test`, output);

  for (const file of report.testResults) {
    for (const test of file.assertionResults) if (test.status === "failed") saveFailure(test);
  }

  const execs = report.numTotalTests * RUNS;
  stats.execsTotal += execs;
  stats.iterations += 1;
  execsPerSecond = execs / ((Date.now() - started) / 1000);
  writeStatus();
  if (stats.iterations % 20 === 0) {
    console.log(
      `STATS iterations=${stats.iterations} execs_total=${stats.execsTotal} execs_per_second=${execsPerSecond.toFixed(0)}`
    );
  }
}

writeStatus();
process.exit(0);
