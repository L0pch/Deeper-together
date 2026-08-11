import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

async function expectNoWcagViolations(page: Page, state: string) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();

  expect(
    results.violations,
    `${state} has accessibility violations:\n${results.violations
      .map((violation) => `${violation.id}: ${violation.help} (${violation.nodes.length} nodes)`)
      .join("\n")}`,
  ).toEqual([]);
}

async function createAccessibilityRoom(page: Page) {
  await page.goto("/create");
  await page.getByLabel("Your display name").fill("Accessibility host");
  await page.getByRole("button", { name: "Create room" }).click();
  await page.waitForURL(/\/room\/[A-HJ-NP-Z2-9]{6}\/lobby$/);
}

test("public routes and keyboard entry meet the automated WCAG baseline", async ({ page }) => {
  for (const route of ["/", "/create", "/join", "/admin"]) {
    await page.goto(route);
    await expectNoWcagViolations(page, route);
  }

  await page.goto("/create");
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "Deeper Together home" })).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "Back home" })).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(page.getByLabel("Your display name")).toBeFocused();
});

test("lobby and game states meet the automated WCAG and mobile-overflow baseline", async ({ page }) => {
  await createAccessibilityRoom(page);
  await expect(page.getByText("Live updates connected")).toBeVisible();
  await expectNoWcagViolations(page, "host lobby");

  await page.getByRole("button", { name: "Start game" }).click();
  await page.getByRole("link", { name: "Enter game" }).click();
  await page.waitForURL(/\/game$/);
  await expect(page.getByRole("heading", { name: "Your turn" })).toBeVisible();
  await expectNoWcagViolations(page, "game before drawing");

  await page.getByRole("button", { name: "Draw a card" }).click();
  await expect(page.getByRole("button", { name: "Draw another card" })).toBeVisible();
  await expectNoWcagViolations(page, "game with a visible prompt");

  await page.setViewportSize({ width: 390, height: 844 });
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await expectNoWcagViolations(page, "mobile game");
});
