"use client";

import { useState } from "react";

import {
  AdminPromptSyncError,
  syncAdminPromptsFromGoogleSheet,
} from "@/lib/admin/prompt-service";
import { getGameErrorMessage } from "@/lib/game/errors";
import type { GoogleSheetSyncResult } from "@/types/admin";

type AdminGoogleSheetSyncProps = {
  onSynced: () => Promise<void>;
};

export function AdminGoogleSheetSync({ onSynced }: AdminGoogleSheetSyncProps) {
  const [isSyncing, setIsSyncing] = useState(false);
  const [result, setResult] = useState<GoogleSheetSyncResult | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleSync() {
    setIsSyncing(true);
    setResult(null);
    setErrorMessage(null);
    try {
      const nextResult = await syncAdminPromptsFromGoogleSheet();
      setResult(nextResult);
      await onSynced();
    } catch (error) {
      setErrorMessage(error instanceof AdminPromptSyncError
        ? error.message
        : getGameErrorMessage(error));
    } finally {
      setIsSyncing(false);
    }
  }

  return (
    <section aria-labelledby="google-sheet-sync-heading" className="rounded-2xl border border-[#d8cbbb] bg-[#fffaf2] p-5 sm:p-6">
      <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--warm)]">Prompt source</p>
      <h2 id="google-sheet-sync-heading" className="mt-1 text-2xl font-semibold text-[var(--accent-strong)]">Private Google Sheet</h2>
      <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
        Your shared sheet is the source of truth. A successful sync updates matching prompts, adds new rows, and archives prompts removed from the sheet. Existing game history never changes.
      </p>
      <p className="mt-2 text-xs leading-5 text-[var(--muted)]">
        Automatic sync runs daily. Use this button after collaborators finish editing for an immediate update.
      </p>
      <button type="button" onClick={() => void handleSync()} disabled={isSyncing} className="mt-4 min-h-12 rounded-full bg-[var(--accent)] px-6 font-semibold text-white hover:bg-[var(--accent-strong)] disabled:cursor-wait disabled:bg-[#8ca097]">
        {isSyncing ? "Synchronizing..." : "Sync Google Sheet now"}
      </button>
      {result ? (
        <p role="status" className="mt-4 rounded-xl bg-[#edf4f0] px-4 py-3 text-sm leading-6 text-[var(--accent-strong)]">
          Synced {result.total} prompts: {result.inserted} added, {result.updated} updated, and {result.archived} archived.
        </p>
      ) : null}
      {errorMessage ? <p role="alert" className="mt-4 text-sm leading-6 text-[#7b3521]">{errorMessage}</p> : null}
    </section>
  );
}
