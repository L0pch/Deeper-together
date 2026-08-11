import { timingSafeEqual } from "node:crypto";

import { syncPromptsFromGoogleSheet } from "@/lib/server/google-sheet-sync";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function secretsMatch(actual: string | null, expected: string): boolean {
  if (!actual?.startsWith("Bearer ")) return false;
  const actualSecret = Buffer.from(actual.slice("Bearer ".length));
  const expectedSecret = Buffer.from(expected);
  return actualSecret.length === expectedSecret.length
    && timingSafeEqual(actualSecret, expectedSecret);
}

export async function GET(request: Request) {
  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret || !secretsMatch(request.headers.get("authorization"), cronSecret)) {
    return Response.json({ error: "Unauthorized." }, { status: 401 });
  }

  try {
    const result = await syncPromptsFromGoogleSheet();
    return Response.json(result);
  } catch {
    return Response.json(
      { error: "Prompt synchronization failed; the existing prompt bank was left unchanged." },
      { status: 500 },
    );
  }
}