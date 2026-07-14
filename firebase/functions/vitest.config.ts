import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Emulator suites share one Firestore instance; serial execution keeps
    // seeded fixtures deterministic.
    fileParallelism: false,
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
