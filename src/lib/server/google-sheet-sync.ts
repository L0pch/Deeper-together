import { GoogleAuth } from "google-auth-library";

import { parseGoogleSheetPromptValues } from "@/lib/admin/prompt-csv";
import { createSupabaseServiceClient } from "@/lib/server/supabase";
import type { GoogleSheetSyncResult } from "@/types/admin";
import type { Json } from "@/types/json";

const sheetsReadonlyScope = "https://www.googleapis.com/auth/spreadsheets.readonly";

type GoogleValuesResponse = {
  values?: unknown[][];
};

function getGoogleSheetConfiguration() {
  const clientEmail = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL?.trim();
  const privateKey = process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY?.replaceAll("\\n", "\n");
  const spreadsheetId = process.env.GOOGLE_SHEETS_SPREADSHEET_ID?.trim();
  const range = process.env.GOOGLE_SHEETS_RANGE?.trim() || "Prompts!A:D";

  if (!clientEmail || !privateKey || !spreadsheetId) {
    throw new Error("google_sheet_sync_not_configured");
  }
  if (!/^[A-Za-z0-9_-]+$/.test(spreadsheetId) || range.length > 120) {
    throw new Error("google_sheet_sync_configuration_invalid");
  }

  return { clientEmail, privateKey, spreadsheetId, range };
}

function parseSyncResult(value: Json | undefined): GoogleSheetSyncResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("google_sheet_sync_response_invalid");
  }

  const { total, inserted, updated, archived, syncedAt } = value;
  if (typeof total !== "number"
    || typeof inserted !== "number"
    || typeof updated !== "number"
    || typeof archived !== "number"
    || typeof syncedAt !== "string") {
    throw new Error("google_sheet_sync_response_invalid");
  }

  return { total, inserted, updated, archived, syncedAt };
}

export async function syncPromptsFromGoogleSheet(): Promise<GoogleSheetSyncResult> {
  const { clientEmail, privateKey, spreadsheetId, range } = getGoogleSheetConfiguration();
  const auth = new GoogleAuth({
    credentials: {
      client_email: clientEmail,
      private_key: privateKey,
    },
    scopes: [sheetsReadonlyScope],
  });
  const authClient = await auth.getClient();
  const headers = await authClient.getRequestHeaders();
  const authorization = headers.get("authorization");
  if (!authorization) throw new Error("google_sheet_authentication_failed");

  const url = new URL(
    "https://sheets.googleapis.com/v4/spreadsheets/"
      + encodeURIComponent(spreadsheetId)
      + "/values/"
      + encodeURIComponent(range),
  );
  url.searchParams.set("majorDimension", "ROWS");
  url.searchParams.set("valueRenderOption", "FORMATTED_VALUE");

  const response = await fetch(url, {
    cache: "no-store",
    headers: { Authorization: authorization },
    signal: AbortSignal.timeout(15_000),
  });

  if (!response.ok) {
    if (response.status === 403) throw new Error("google_sheet_access_denied");
    if (response.status === 404) throw new Error("google_sheet_not_found");
    throw new Error("google_sheet_request_failed");
  }

  const payload = await response.json() as GoogleValuesResponse;
  if (!Array.isArray(payload.values)) throw new Error("google_sheet_empty");
  const rows = parseGoogleSheetPromptValues(payload.values);

  const serviceClient = createSupabaseServiceClient();
  const { data, error } = await serviceClient.rpc("sync_google_sheet_prompts", {
    p_rows: rows,
  });
  if (error) throw error;

  return parseSyncResult(data);
}