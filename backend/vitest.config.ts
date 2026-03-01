import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    env: { LOG_LEVEL: 'error' },
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
    },
    testTimeout: 15_000,
  },
});
