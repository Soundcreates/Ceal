import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    env: {
      LOG_LEVEL: 'error',
      NODE_ENV: 'test',
      DATABASE_URL: 'postgresql://test:test@localhost:5432/ceal_test',
      BLE_ENCRYPTION_SECRET: '0123456789abcdef0123456789abcdef',
      JWT_SECRET: '0123456789abcdef0123456789abcdef',
      SERVER_SECRET: 'server-secret-for-tests-0123456789',
    },
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
    },
    testTimeout: 15_000,
  },
});
