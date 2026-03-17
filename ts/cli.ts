import {readFileSync} from "node:fs";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";
import {parseArgs} from "node:util";
import {buildCli} from "./build.js";
import {buildArtifactsCli} from "./buildArtifacts.js";
import {logError} from "./log.js";
import {prepublishCli} from "./prepublish.js";
import {publishCli} from "./publish.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const {version} = JSON.parse(readFileSync(join(__dirname, "..", "package.json"), "utf-8"));

const HELP = `
zapi - Build and publish Zig N-API packages

Usage: zapi <command> [options]

Commands:
  build             Build for a single target
      --target      Target triple (default: current platform)
      --optimize    Optimization level: Debug, ReleaseSafe, ReleaseFast, ReleaseSmall
      --step        Zig build step (required)
      --zig-cwd     Working directory for zig build (default: .)

  build-artifacts   Build for all configured targets
      --optimize       Optimization level
      --step           Zig build step (required)
      --zig-cwd        Working directory for zig build (default: .)
      --artifacts-dir  Output directory for artifacts (default: artifacts)
      --concurrency    Parallel target builds (default: min(cpu, 4))

  prepublish        Prepare npm packages for publishing
      --artifacts-dir  Directory containing built artifacts (default: artifacts)
      --npm-dir        Directory for npm packages (default: npm)
      --concurrency    Parallel filesystem prep jobs (default: min(cpu, 4))

  publish           Publish all packages to npm
      --npm-dir        Directory containing npm packages (default: npm)
      --dry-run        Preview what would be published without publishing
      --concurrency    Parallel target publishes (default: 1)
      [-- <npm-args>]  Additional arguments passed to npm publish

Options:
  --help, -h        Show this help message
  --version, -v     Show version number

Configuration:
  Add a "zapi" field to your package.json:
  {
    "zapi": {
      "binaryName": "my-addon",
      "targets": ["x86_64-unknown-linux-gnu", "aarch64-apple-darwin", ...]
    }
  }
`.trim();

export async function cli(): Promise<void> {
  const {positionals, values} = parseArgs({
    allowPositionals: true,
    options: {
      help: {short: "h", type: "boolean"},
      version: {short: "v", type: "boolean"},
    },
    strict: false,
  });

  if (values.version) {
    console.log(`zapi ${version}`);
    return;
  }

  if (values.help || positionals.length === 0) {
    console.log(HELP);
    return;
  }

  const cmd = positionals[0];

  switch (cmd) {
    case "build":
      return await buildCli();
    case "build-artifacts":
      return await buildArtifactsCli();
    case "prepublish":
      return await prepublishCli();
    case "publish":
      return await publishCli();
    case "help":
      console.log(HELP);
      return;
    default:
      console.error(`Unknown command "${cmd}"\n`);
      console.log(HELP);
      process.exit(1);
  }
}

try {
  await cli();
} catch (err) {
  if (err instanceof Error) {
    logError(err.message);
    if (process.env.DEBUG) {
      console.error(err.stack);
    }
  } else {
    logError(String(err));
  }
  process.exit(1);
}
