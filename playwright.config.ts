import { defineConfig, devices } from "@playwright/test";

const localBaseURL = "http://127.0.0.1:3100";
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? localBaseURL;

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 90_000,
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  expect: { timeout: 10_000 },
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: process.env.CI ? [["line"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: process.env.CI && !process.env.PLAYWRIGHT_BASE_URL
    ? {
        command: "node node_modules/next/dist/bin/next start --hostname 127.0.0.1 --port 3100",
        url: localBaseURL,
        reuseExistingServer: false,
        stderr: "ignore",
        stdout: "ignore",
        timeout: 120_000,
      }
    : undefined,
});
