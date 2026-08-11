import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type {
  AdminPrompt,
  AdminPromptCatalog,
  AdminPromptCategory,
  AdminPromptFilters,
  AdminPromptInput,
  AdminPromptImportResult,
  AdminPromptStateAction,
  AdminPromptTransferRow,
  GoogleSheetSyncResult,
} from "@/types/admin";
import type { Json } from "@/types/json";

export class AdminPromptSyncError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AdminPromptSyncError";
  }
}

function asRecord(value: Json | undefined): Record<string, Json | undefined> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_admin_response");
  }
  return value;
}

function asString(value: Json | undefined): string {
  if (typeof value !== "string") throw new Error("invalid_admin_response");
  return value;
}

function asBoolean(value: Json | undefined): boolean {
  if (typeof value !== "boolean") throw new Error("invalid_admin_response");
  return value;
}

function asArray(value: Json | undefined): Json[] {
  if (!Array.isArray(value)) throw new Error("invalid_admin_response");
  return value;
}

function parseCategory(value: Json): AdminPromptCategory {
  const record = asRecord(value);
  return {
    id: asString(record.id),
    label: asString(record.label),
    isActive: asBoolean(record.isActive),
  };
}

function parsePrompt(value: Json): AdminPrompt {
  const record = asRecord(value);
  const level = record.level;
  if (level !== 1 && level !== 2 && level !== 3) throw new Error("invalid_admin_response");

  return {
    id: asString(record.id),
    promptText: asString(record.promptText),
    level,
    categoryId: asString(record.categoryId),
    categoryLabel: asString(record.categoryLabel),
    isActive: asBoolean(record.isActive),
    archivedAt: record.archivedAt === null ? null : asString(record.archivedAt),
    createdAt: asString(record.createdAt),
    updatedAt: asString(record.updatedAt),
  };
}

export function parseAdminPromptCatalog(value: Json | undefined): AdminPromptCatalog {
  const record = asRecord(value);
  if (typeof record.total !== "number") throw new Error("invalid_admin_response");

  return {
    prompts: asArray(record.prompts).map(parsePrompt),
    categories: asArray(record.categories).map(parseCategory),
    total: record.total,
  };
}

export async function fetchAdminPromptCatalog(
  filters: AdminPromptFilters,
): Promise<AdminPromptCatalog> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("get_admin_prompt_catalog", {
    p_search: filters.search || null,
    p_level: filters.level,
    p_category_id: filters.categoryId,
    p_status: filters.status,
    p_limit: 100,
    p_offset: 0,
  });

  if (error) throw error;
  return parseAdminPromptCatalog(data);
}

export async function saveAdminPrompt(input: AdminPromptInput): Promise<AdminPrompt> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("save_admin_prompt", {
    p_prompt_text: input.promptText,
    p_level: input.level,
    p_category_id: input.categoryId,
    p_prompt_id: input.id ?? null,
  });

  if (error) throw error;
  return parsePrompt(data);
}

export async function setAdminPromptState(
  promptId: string,
  action: AdminPromptStateAction,
): Promise<AdminPrompt> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("set_admin_prompt_state", {
    p_prompt_id: promptId,
    p_action: action,
  });

  if (error) throw error;
  return parsePrompt(data);
}

export async function importAdminPrompts(
  rows: AdminPromptTransferRow[],
): Promise<AdminPromptImportResult> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("import_admin_prompts", {
    p_rows: rows,
  });

  if (error) throw error;
  const record = asRecord(data);
  if (typeof record.total !== "number"
    || typeof record.imported !== "number"
    || typeof record.skipped !== "number") {
    throw new Error("invalid_admin_response");
  }
  return {
    total: record.total,
    imported: record.imported,
    skipped: record.skipped,
  };
}

export async function fetchAdminPromptExport(): Promise<AdminPromptTransferRow[]> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("get_admin_prompt_export");

  if (error) throw error;
  return asArray(data).map((value) => {
    const record = asRecord(value);
    const level = record.level;
    const status = record.status;
    if ((level !== 1 && level !== 2 && level !== 3)
      || (status !== "active" && status !== "inactive" && status !== "archived")) {
      throw new Error("invalid_admin_response");
    }
    return {
      promptText: asString(record.promptText),
      level,
      categoryId: asString(record.categoryId),
      status,
    };
  });
}
export async function syncAdminPromptsFromGoogleSheet(): Promise<GoogleSheetSyncResult> {
  const supabase = getSupabaseBrowserClient();
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) throw sessionError;

  const accessToken = sessionData.session?.access_token;
  if (!accessToken) throw new Error("admin_strong_authentication_required");

  const response = await fetch("/api/admin/prompts/sync", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + accessToken,
    },
  });
  const payload = await response.json() as Json;
  if (!response.ok) {
    const record = asRecord(payload);
    throw new AdminPromptSyncError(typeof record.error === "string"
      ? record.error
      : "The Google Sheet could not be synchronized.");
  }

  const record = asRecord(payload);
  if (typeof record.total !== "number"
    || typeof record.inserted !== "number"
    || typeof record.updated !== "number"
    || typeof record.archived !== "number"
    || typeof record.syncedAt !== "string") {
    throw new Error("google_sheet_sync_response_invalid");
  }

  return {
    total: record.total,
    inserted: record.inserted,
    updated: record.updated,
    archived: record.archived,
    syncedAt: record.syncedAt,
  };
}
