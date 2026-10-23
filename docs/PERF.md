# Performance

Measured 2026-10-23 on Roben's MacBook Pro (Apple M1 Max, 10 cores, 32 GB, macOS 27.0.1, internal SSD, 13 GiB used of 460 GiB). `~/Library/Caches` is 804 MB and `~/Pictures` 13 MB, so this is a small home folder; the numbers show relative behaviour, not a stress test.

How: `TEST_RUNNER_FILKOLLEN_PERF=1 xcodebuild test -only-testing:FilkollenTests/PerfTests` (`FilkollenTests/PerfTests.swift`). It times each live scanner against the real home folder, read-only. The same file was run against the audit baseline `479b962` in a worktree.

## Results (seconds)

| Scanner | Baseline 479b962 | Now, cold hash cache | Now, warm hash cache |
|---|---|---|---|
| System Junk (120–121 items) | 2.93 / 0.24 | 3.13 | 0.19 |
| App Leftovers | 0.10 / 0.11 | 0.08 | 0.09 |
| Duplicate Photos (646 items) | 3.10 / 0.48 | 2.76 | 0.33–0.36 |
| Large Files | 0.43 / 0.43 | 0.45 | 0.45 |

Baseline figures are first run / second run, both with a warm OS file cache.

The very first run of the session, with the OS file cache cold, took 111 s for duplicates and 4.5 s for System Junk. That is the disk being read for the first time, not code: every later run, on either version, was a few seconds.

## What changed

- **Duplicates:** size → first 64 KB → last 64 KB → full SHA-256, each tier hashed on all cores, and hashes cached by device + inode + size + mtime. Cold: ~11% faster than baseline here; warm: ~25% faster, and only changed files are re-read. The gap grows with the number of same-size photos (RAW libraries, burst shots), where the tail tier and the cache avoid full reads.
- **System Junk:** cache folders are measured in parallel. On this small cache set the difference is within noise (0.19 s vs 0.24 s warm).
- **Smart Scan:** categories now run concurrently, so a Smart Scan takes roughly as long as its slowest scanner instead of the sum.
- Totals differ slightly from baseline (System Junk 1.79 GB vs 1.88 GB; duplicates 87.6 MB vs 85.7 MB) because sizes are now allocated sizes with hard links counted once and symlinks counted as nothing.

## Next

- Re-profile on a large home folder (100k+ photos, multi-GB caches) to size the parallelism. `parallelMap` currently uses every core, which may be too aggressive on spinning or network disks.
- The malware scan has its own parallel hashing and cache (PR #2) and isn't covered by `PerfTests` yet.
