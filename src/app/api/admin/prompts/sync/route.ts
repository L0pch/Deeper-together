import { syncPromptsFromGoogleSheet } from "@/lib/server/google-sheet-sync";
import { createSupabaseUserClient } from "@/lib/server/supabase";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function getBearerToken(request: Request): string | null {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return null;
  return authorization.slice("Bearer ".length).trim() || null;
}

function safeSyncError(error: unknown): { message: string; status: number } {
  const message = error instanceof Error ? error.message : "";
  if (message.includes("google_sheet_sync_not_configured")) {
    return { message: "Google Sheet sync has not been configured yet.", status: 503 };
  }
  if (message.includes("google_sheet_access_denied")) {
    return { message: "The service account cannot read this Google Sheet. Share the sheet with its email address as a Viewer.", status: 502 };
  }
  if (message.includes("google_sheet_not_found")) {
    return { message: "The configured Google Sheet or tab could not be found.", status: 502 };
  }
  if (message.includes("Include a header row") || message.includes("Row ") || message.includes("missing the")) {
    return { message, status: 422 };
  }
  if (message.includes("duplicate_prompt_sync_text")) {
    return { message: "The Google Sheet contains duplicate prompt text.", status: 422 };
  }
  if (message.includes("invalid_prompt_sync_category")) {
    return { message: "The Google Sheet contains a category that is not available.", status: 422 };
  }
  return { message: "The Google Sheet could not be synchronized. The existing prompt bank was left unchanged.", status: 502 };
}

export async function POST(request: Request) {
  const accessToken = getBearerToken(request);
  if (!accessToken) {
    return Response.json({ error: "Administrator sign-in is required." }, { status: 401 });
  }

  try {
    const userClient = createSupabaseUserClient(accessToken);
    const { error: authorizationError } = await userClient.rpc("get_admin_prompt_catalog", {
      p_search: null,
      p_level: null,
      p_category_id: null,
      p_status: "all",
      p_limit: 1,
      p_offset: 0,
    });
    if (authorizationError) {
      return Response.json({ error: "Administrator permission is required." }, { status: 403 });
    }

    const result = await syncPromptsFromGoogleSheet();
    return Response.json(result);
  } catch (error) {
    const safeError = safeSyncError(error);
    return Response.json({ error: safeError.message }, { status: safeError.status });
  }
}