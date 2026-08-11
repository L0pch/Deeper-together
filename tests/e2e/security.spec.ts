import { expect, test } from "@playwright/test";

test("all application responses include the baseline security headers", async ({ request }) => {
  for (const route of ["/", "/create", "/join", "/admin"]) {
    const response = await request.get(route);
    const contentSecurityPolicy = response.headers()["content-security-policy"];

    expect(response.ok(), `${route} should return a successful response`).toBe(true);
    expect(contentSecurityPolicy).toContain("default-src 'self'");
    expect(contentSecurityPolicy).toContain("connect-src 'self'");
    expect(contentSecurityPolicy).toContain("frame-ancestors 'none'");
    expect(contentSecurityPolicy).toContain("frame-src 'none'");
    expect(contentSecurityPolicy).toContain("media-src 'none'");
    expect(contentSecurityPolicy).toContain("object-src 'none'");
    expect(contentSecurityPolicy).not.toContain("unsafe-eval");
    expect(response.headers()["permissions-policy"]).toBe(
      "camera=(), microphone=(), geolocation=(), browsing-topics=()",
    );
    expect(response.headers()["referrer-policy"]).toBe(
      "strict-origin-when-cross-origin",
    );
    expect(response.headers()["x-content-type-options"]).toBe("nosniff");
    expect(response.headers()["x-frame-options"]).toBe("DENY");
    expect(response.headers()["x-powered-by"]).toBeUndefined();
    expect(response.headers()["strict-transport-security"]).toBeUndefined();
  }
});
