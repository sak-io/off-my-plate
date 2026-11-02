import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "tests",
  timeout: 180_000,
  workers: 1,
  reporter: [["list"]],
  use: { baseURL: "http://127.0.0.1:4173", browserName: "chromium", launchOptions: { args: [] } },
  webServer: { command: "node scripts/serve.mjs 4173", url: "http://127.0.0.1:4173/index.html", reuseExistingServer: false, timeout: 30_000 },
});
