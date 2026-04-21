# Changelog

## [1.0.1](https://github.com/ChainSafe/zapi/compare/zapi-v1.0.0...zapi-v1.0.1) (2026-04-21)


### Bug Fixes

* package url for provenance ([#17](https://github.com/ChainSafe/zapi/issues/17)) ([893a357](https://github.com/ChainSafe/zapi/commit/893a357e03cedfa0b47dd82f4a748068389cbb1b))

## [1.0.0](https://github.com/ChainSafe/zapi/compare/zapi-v0.1.0...zapi-v1.0.0) (2026-04-21)


### ⚠ BREAKING CHANGES

* use zapi namespace ([#12](https://github.com/ChainSafe/zapi/issues/12))

### Features

* add AsyncWork, allow Callback to error ([696fcba](https://github.com/ChainSafe/zapi/commit/696fcba6a52b2d4d5a938cb00e11eee8704c0f6f))
* add more napi features ([b719441](https://github.com/ChainSafe/zapi/commit/b719441b813b31c93fe6997be95a6bc7b2cf64b6))
* add Raw variant functions for callFunction, newInstance, makeCallback ([#8](https://github.com/ChainSafe/zapi/issues/8)) ([d3c86be](https://github.com/ChainSafe/zapi/commit/d3c86be360fb2f0a8bac0f927f9642e04234780a))
* add threadsafe function queue size default ([#4](https://github.com/ChainSafe/zapi/issues/4)) ([8aa5358](https://github.com/ChainSafe/zapi/commit/8aa535872ca0c3d332eeb327264190c0ab53fd10))
* add ThreadSafeFunction ([8ac058a](https://github.com/ChainSafe/zapi/commit/8ac058a4061b13e28b2f1ed9fa56b88881211cf3))
* add TypedarrayType.elementType ([cf01345](https://github.com/ChainSafe/zapi/commit/cf013457cdf0612a62a6d008d65505ff79e85596))
* add typescript management library ([89d87a8](https://github.com/ChainSafe/zapi/commit/89d87a89c02749596bc98411ddf12fe7456b1932))
* allow env and value params/return in callback ([32499ff](https://github.com/ChainSafe/zapi/commit/32499fff12e8d0e9c75ed77f65f78baa76a58603))
* better callback error name ([9c69292](https://github.com/ChainSafe/zapi/commit/9c69292e81822fc58fa4af3f4679cf78702790ee))
* CallbackInfo generic on argc ([5c2cd2a](https://github.com/ChainSafe/zapi/commit/5c2cd2a70715668e8b5d8565fdb53af123f37b8f))
* configurable napi version ([9aa9271](https://github.com/ChainSafe/zapi/commit/9aa92712b347fff6b7498146136839f78898fa3d))
* get/setInstanceData, add/removeEnvCleanupHook ([5f28202](https://github.com/ChainSafe/zapi/commit/5f2820278bc1d55e56bccdcbe854eafaae695d8f))
* **js:** add high-level DSL with JS-aligned types ([#11](https://github.com/ChainSafe/zapi/issues/11)) ([997b1fe](https://github.com/ChainSafe/zapi/commit/997b1fe8e3b21725ce67ed0e8e9e2900f9bbd7e9))
* make getLastErrorInfo safer ([281b326](https://github.com/ChainSafe/zapi/commit/281b3262bc6bfb77fc298ef65c921b19f7b709ef))
* more typesafe wrap ([2e6b7fa](https://github.com/ChainSafe/zapi/commit/2e6b7fa2c09af7dc3f3231ff5585ffd51bb6dba7))
* parallel target builds with concurrency control ([#3](https://github.com/ChainSafe/zapi/issues/3)) ([e91c11b](https://github.com/ChainSafe/zapi/commit/e91c11bbaa43006643102eb8e5609cf0b688c449))
* refresh ts code ([27ec2e9](https://github.com/ChainSafe/zapi/commit/27ec2e99dd19afb3538afc3cb9ae49b10091b830))
* remove Value.nullptr ([50da3b1](https://github.com/ChainSafe/zapi/commit/50da3b1e0d6e406a874f747336d13442e96414e4))
* throwLastErrorInfo ([f035c43](https://github.com/ChainSafe/zapi/commit/f035c436e6088e77e47037cebe5baf0164a15517))
* type-tag-aware unwrap and removeWrap ([#7](https://github.com/ChainSafe/zapi/issues/7)) ([c7f1e21](https://github.com/ChainSafe/zapi/commit/c7f1e21acf85013fee508c437113b8f41b9440f6))
* typesafe removeWrap ([61dbc38](https://github.com/ChainSafe/zapi/commit/61dbc3895e2f9c6f49393511938c4584d92a0b5f))
* untyped finalize hint ([4f8c9b1](https://github.com/ChainSafe/zapi/commit/4f8c9b19276704f25dab44ac80be975af048e657))
* use zapi namespace ([#12](https://github.com/ChainSafe/zapi/issues/12)) ([5a51cf2](https://github.com/ChainSafe/zapi/commit/5a51cf21121372451bd56af97db896f474bce384))
* Value.isPromise ([e604d49](https://github.com/ChainSafe/zapi/commit/e604d494d632d8c3bc72d3320688313aba963fe5))


### Bug Fixes

* allow createFunction data to be null ([9120421](https://github.com/ChainSafe/zapi/commit/9120421f704ce5c0e7ec1c894b7274eb27c7c031))
* allow undefined symbols during build time ([#1](https://github.com/ChainSafe/zapi/issues/1)) ([085c03b](https://github.com/ChainSafe/zapi/commit/085c03b1aeabf2489e25cab18455d342e342ebab))
* buggy arraybuffer / buffer creation ([f820a6e](https://github.com/ChainSafe/zapi/commit/f820a6e2c1eade08edbe0faf108f8b3dd1805dd8))
* callFunction bug ([ca9e2fc](https://github.com/ChainSafe/zapi/commit/ca9e2fcfd6d8fe8fd641e3da752ede9bb2373f1f))
* fatalError return type ([4a83d97](https://github.com/ChainSafe/zapi/commit/4a83d97eb11004f0dca41572f54a3be2f9398d54))
* remove yarn files ([c02bf9f](https://github.com/ChainSafe/zapi/commit/c02bf9fb9ecc4aa28afe6ef4e71ed68587377e5a))
* safer callback handling and argument validation ([#5](https://github.com/ChainSafe/zapi/issues/5)) ([223afa5](https://github.com/ChainSafe/zapi/commit/223afa5ecafb277edcf3d73e9c5a8c70516d34e0))
* safer integer conversion and external buffer support ([#6](https://github.com/ChainSafe/zapi/issues/6)) ([ff0f0c8](https://github.com/ChainSafe/zapi/commit/ff0f0c85fee58245d9be035a65d6f94795814a8b))
* throw*Error type fixes ([354e36d](https://github.com/ChainSafe/zapi/commit/354e36d4f52c0f79ca34ad588700c423b2ee3988))
* use createRequire ([7d4f5fd](https://github.com/ChainSafe/zapi/commit/7d4f5fdc710bf628ff328d5c92033ad832cc7b6e))
* use napi_version option ([fe1589c](https://github.com/ChainSafe/zapi/commit/fe1589c322aab857eb1fa8e28baae8e8dbcfd393))
* various bugs ([ed2af49](https://github.com/ChainSafe/zapi/commit/ed2af49093bf4faeb36076d15c8272d8001b15a4))
