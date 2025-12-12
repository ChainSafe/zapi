import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const example = require('../zig-out/lib/example.node');

console.log(example.add(1, 2));
console.log(example.surprise());
