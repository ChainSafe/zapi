/**
 * Simple logging utilities with colored output for CLI progress indicators.
 */

const COLORS = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
  magenta: "\x1b[35m",
} as const;

function supportsColor(): boolean {
  if (process.env.NO_COLOR) return false;
  if (process.env.FORCE_COLOR) return true;
  return process.stdout.isTTY ?? false;
}

function colorize(color: keyof typeof COLORS, text: string): string {
  if (!supportsColor()) return text;
  return `${COLORS[color]}${text}${COLORS.reset}`;
}

/**
 * Log a step in a multi-step process.
 * Example: [1/6] Building for x86_64-unknown-linux-gnu...
 */
export function logStep(current: number, total: number, message: string): void {
  const prefix = colorize("cyan", `[${current}/${total}]`);
  console.log(`${prefix} ${message}`);
}

/**
 * Log the start of a command/phase.
 * Example: ▶ Building artifacts...
 */
export function logInfo(message: string): void {
  const prefix = colorize("blue", "▶");
  console.log(`${prefix} ${message}`);
}

/**
 * Log a success message.
 * Example: ✓ Build complete
 */
export function logSuccess(message: string): void {
  const prefix = colorize("green", "✓");
  console.log(`${prefix} ${message}`);
}

/**
 * Log a warning message.
 * Example: ⚠ Artifact not found
 */
export function logWarn(message: string): void {
  const prefix = colorize("yellow", "⚠");
  console.warn(`${prefix} ${message}`);
}

/**
 * Log a detail/sub-step (indented, dimmed).
 * Example:   → Moving to artifacts/x86_64-linux-gnu/
 */
export function logDetail(message: string): void {
  const prefix = colorize("dim", "  →");
  console.log(`${prefix} ${colorize("dim", message)}`);
}

/**
 * Log an error message.
 * Example: ✗ Build failed
 */
export function logError(message: string): void {
  const red = "\x1b[31m";
  const reset = "\x1b[0m";
  const prefix = supportsColor() ? `${red}✗${reset}` : "✗";
  const text = supportsColor() ? `${red}${message}${reset}` : message;
  console.error(`${prefix} ${text}`);
}
