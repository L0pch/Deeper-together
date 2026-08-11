import { expect, test, type BrowserContext, type Page } from "@playwright/test";

const roomPath = /\/room\/([A-HJ-NP-Z2-9]{6})\/lobby$/;

async function createRoom(page: Page, displayName: string) {
  await page.goto("/create");
  await page.getByLabel("Your display name").fill(displayName);
  await page.getByRole("button", { name: "Create room" }).click();
  await page.waitForURL(roomPath);

  const match = new URL(page.url()).pathname.match(roomPath);
  if (!match) throw new Error("Created room URL did not contain a room code.");
  return match[1];
}

async function joinRoom(page: Page, roomCode: string, displayName: string) {
  await page.goto(`/join?code=${roomCode}`);
  await expect(page.getByLabel("Room code")).toHaveValue(roomCode);
  await page.getByLabel("Your display name").fill(displayName);
  await page.getByRole("button", { name: "Join room" }).click();
  await page.waitForURL(`/room/${roomCode}/lobby`);
}

async function enterGame(page: Page) {
  await page.getByRole("link", { name: "Enter game" }).click();
  await page.waitForURL(/\/game$/);
  await expect(page.getByText("Player queue")).toBeVisible();
}

async function setOffline(context: BrowserContext, offline: boolean) {
  await context.setOffline(offline);
}

function acceptNextConfirmation(page: Page, expectedMessage: string) {
  return new Promise<void>((resolve, reject) => {
    page.once("dialog", async (dialog) => {
      try {
        expect(dialog.message()).toContain(expectedMessage);
        await dialog.accept();
        resolve();
      } catch (error) {
        reject(error);
      }
    });
  });
}

test("late join, realtime recovery, refresh, redraw, and turn advancement stay authoritative", async ({ browser }) => {
  const hostContext = await browser.newContext();
  const guestContext = await browser.newContext();
  const hostPage = await hostContext.newPage();
  const guestPage = await guestContext.newPage();

  try {
    const roomCode = await createRoom(hostPage, "Host player");

    await expect(hostPage.getByText("1 of 20 players")).toBeVisible();
    await expect(hostPage.getByText("Live updates connected")).toBeVisible();
    await hostPage.getByRole("button", { name: "Start game" }).click();
    await expect(hostPage.getByRole("link", { name: "Enter game" })).toBeVisible();

    await joinRoom(guestPage, roomCode, "Late guest");
    await expect(guestPage.getByText("Live updates connected")).toBeVisible();

    await expect(hostPage.getByText("2 of 20 players")).toBeVisible();
    await expect(
      hostPage.getByRole("region", { name: "Players" }).getByRole("listitem").filter({ hasText: "Late guest" }),
    ).toBeVisible();
    await expect(
      guestPage.getByRole("region", { name: "Players" }).getByRole("listitem").filter({ hasText: "Host player" }),
    ).toBeVisible();

    await enterGame(hostPage);
    await enterGame(guestPage);

    const hostQueue = hostPage.locator('section[aria-labelledby="queue-heading"] li');
    await expect(hostQueue).toHaveCount(2);
    await expect(hostQueue.nth(0)).toContainText("Host player (you)");
    await expect(hostQueue.nth(0)).toContainText("Current player");
    await expect(hostQueue.nth(1)).toContainText("Late guest");
    await expect(hostPage.getByRole("heading", { name: "Your turn" })).toBeVisible();
    await expect(guestPage.getByText("Listening while Host player takes their turn.")).toBeVisible();

    await setOffline(guestContext, true);
    await hostPage.getByRole("button", { name: "Draw a card" }).click();
    await expect(hostPage.getByRole("button", { name: "Draw another card" })).toBeVisible();
    const firstPrompt = await hostPage.locator("#prompt-heading").innerText();
    await expect(hostPage.getByText("Prompt history (1)")).toBeVisible();

    await setOffline(guestContext, false);
    await expect(guestPage.locator("#prompt-heading")).toHaveText(firstPrompt, { timeout: 20_000 });
    await expect(guestPage.getByText("Prompt history (1)")).toBeVisible();

    await hostPage.reload();
    await expect(hostPage.getByRole("heading", { name: "Your turn" })).toBeVisible();
    await expect(hostPage.locator("#prompt-heading")).toHaveText(firstPrompt);
    await expect(hostPage.locator('section[aria-labelledby="queue-heading"] li')).toHaveCount(2);

    await hostPage.getByRole("button", { name: "Draw another card" }).click();
    await expect(hostPage.getByText("Prompt history (2)")).toBeVisible();
    await expect(guestPage.getByText("Prompt history (2)")).toBeVisible();

    await hostPage.getByRole("button", { name: "Done sharing" }).click();
    await expect(hostPage.getByText("Listening while Late guest takes their turn.")).toBeVisible();
    await expect(guestPage.getByRole("heading", { name: "Your turn" })).toBeVisible();

    await guestPage.reload();
    await expect(guestPage.getByRole("heading", { name: "Your turn" })).toBeVisible();
    await expect(guestPage.locator('section[aria-labelledby="queue-heading"] li')).toHaveCount(2);
  } finally {
    await hostContext.close();
    await guestContext.close();
  }
});

test("host controls synchronize locking, play now, host transfer, and kicking", async ({ browser }) => {
  const hostContext = await browser.newContext();
  const successorContext = await browser.newContext();
  const priorityContext = await browser.newContext();
  const blockedContext = await browser.newContext();
  const hostPage = await hostContext.newPage();
  const successorPage = await successorContext.newPage();
  const priorityPage = await priorityContext.newPage();
  const blockedPage = await blockedContext.newPage();

  try {
    const roomCode = await createRoom(hostPage, "Original host");
    await expect(hostPage.getByText("Live updates connected")).toBeVisible();

    await joinRoom(successorPage, roomCode, "Next host");
    await joinRoom(priorityPage, roomCode, "Priority player");
    await expect(hostPage.getByText("3 of 20 players")).toBeVisible();

    await hostPage.getByRole("button", { name: "Lock room" }).click();
    await expect(hostPage.getByText("Room locked")).toBeVisible();
    await expect(successorPage.getByText("Room locked")).toBeVisible();

    await blockedPage.goto(`/join?code=${roomCode}`);
    await blockedPage.getByLabel("Your display name").fill("Blocked player");
    await blockedPage.getByRole("button", { name: "Join room" }).click();
    await expect(blockedPage.getByText("That room is currently locked by its host.", { exact: true })).toBeVisible();

    await hostPage.getByRole("button", { name: "Unlock room" }).click();
    await expect(hostPage.getByText("Room open")).toBeVisible();
    await hostPage.getByRole("button", { name: "Start game" }).click();

    await enterGame(hostPage);
    await enterGame(successorPage);
    await enterGame(priorityPage);

    await expect(successorPage.getByLabel("Manage Original host")).toHaveCount(0);
    await hostPage.getByLabel("Manage Priority player").click();
    const playNowConfirmation = acceptNextConfirmation(hostPage, "let Priority player play now");
    await hostPage.getByRole("button", { name: "Play now" }).click();
    await playNowConfirmation;

    await expect(priorityPage.getByRole("heading", { name: "Your turn" })).toBeVisible();
    await expect(hostPage.getByText("Listening while Priority player takes their turn.")).toBeVisible();

    const reorderedQueue = hostPage.locator('section[aria-labelledby="queue-heading"] li');
    await expect(reorderedQueue).toHaveCount(3);
    await expect(reorderedQueue.nth(0)).toContainText("Priority player");
    await expect(reorderedQueue.nth(1)).toContainText("Original host (you)");
    await expect(reorderedQueue.nth(2)).toContainText("Next host");

    await hostPage.getByLabel("Manage Next host").click();
    const hostTransferConfirmation = acceptNextConfirmation(hostPage, "Make Next host the new host");
    await hostPage.getByRole("button", { name: "Make host" }).click();
    await hostTransferConfirmation;

    await expect(hostPage.getByLabel("Manage Next host")).toHaveCount(0);
    await expect(successorPage.getByLabel("Manage Original host")).toBeVisible();
    await expect(
      successorPage.locator('section[aria-labelledby="queue-heading"] li').filter({ hasText: "Next host" }),
    ).toContainText("Host");

    await successorPage.getByLabel("Manage Original host").click();
    const kickConfirmation = acceptNextConfirmation(successorPage, "Remove Original host");
    await successorPage.getByRole("button", { name: "Kick player" }).click();
    await kickConfirmation;

    await expect(hostPage.getByText("You were removed from this room by its host.", { exact: true })).toBeVisible();
    await expect(successorPage.locator('section[aria-labelledby="queue-heading"] li')).toHaveCount(2);
    await expect(priorityPage.locator('section[aria-labelledby="queue-heading"] li')).toHaveCount(2);
  } finally {
    await hostContext.close();
    await successorContext.close();
    await priorityContext.close();
    await blockedContext.close();
  }
});
test("room code copy writes the invitation code to the clipboard", async ({ browser }) => {
  const context = await browser.newContext({
    permissions: ["clipboard-read", "clipboard-write"],
  });
  const page = await context.newPage();

  try {
    const roomCode = await createRoom(page, "Clipboard host");
    await page.getByRole("button", { name: "Copy code" }).click();
    await expect(page.getByRole("button", { name: "Copied" })).toBeVisible();
    await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(roomCode);
  } finally {
    await context.close();
  }
});
