# Frozen iztro differential oracle

Install with `npm ci --ignore-scripts` in this directory, then run the repository's
`python -m pytest tests/differential/test_iztro_palace_parity.py` with its Python
dependencies installed.

The independent reference engine is the official npm `iztro` release **2.6.1**.
`package-lock.json` pins the package and every transitive dependency. The iztro
SHA-512 integrity hash is unchanged from the original local-tarball lock; only
the unavailable `data/vendor` tarball location was replaced by the official npm
registry URL. npm verifies the bytes against that hash during `npm ci`.

This runtime is test-only and must never be imported by the production engine.
The seeded 2,080-chart corpus is deliberately restricted to post-DST +08:00 dates;
it is not evidence for all historical time zones or alternative schools.
