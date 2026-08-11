"use client";

import { useRef, useState } from "react";

import {
  createAdminPromptCsvTemplate,
  parseAdminPromptCsv,
  serializeAdminPromptCsv,
} from "@/lib/admin/prompt-csv";
import { fetchAdminPromptExport, importAdminPrompts } from "@/lib/admin/prompt-service";
import { getGameErrorMessage } from "@/lib/game/errors";
import type {
  AdminPromptCategory,
  AdminPromptImportResult,
  AdminPromptTag,
  AdminPromptTransferRow,
} from "@/types/admin";

type AdminImportExportProps = {
  categories: AdminPromptCategory[];
  onImported: () => Promise<void>;
  tags: AdminPromptTag[];
};

function downloadCsv(contents: string, filename: string) {
  const url = URL.createObjectURL(new Blob([contents], { type: "text/csv;charset=utf-8" }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.hidden = true;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

export function AdminImportExport({ categories, onImported, tags }: AdminImportExportProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [pendingRows, setPendingRows] = useState<AdminPromptTransferRow[] | null>(null);
  const [selectedFilename, setSelectedFilename] = useState<string | null>(null);
  const [result, setResult] = useState<AdminPromptImportResult | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [activeAction, setActiveAction] = useState<"import" | "export" | null>(null);

  async function handleFile(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    setPendingRows(null);
    setResult(null);
    setErrorMessage(null);
    setSelectedFilename(file?.name ?? null);
    if (!file) return;
    if (file.size > 1_000_000) {
      setErrorMessage("Choose a CSV file smaller than 1 MB.");
      return;
    }
    try {
      setPendingRows(parseAdminPromptCsv(await file.text(), categories, tags));
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "That CSV could not be read.");
    }
  }

  async function handleImport() {
    if (!pendingRows) return;
    setActiveAction("import");
    setErrorMessage(null);
    try {
      const nextResult = await importAdminPrompts(pendingRows);
      setResult(nextResult);
      setPendingRows(null);
      setSelectedFilename(null);
      if (inputRef.current) inputRef.current.value = "";
      await onImported();
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setActiveAction(null);
    }
  }

  async function handleExport() {
    setActiveAction("export");
    setErrorMessage(null);
    try {
      const rows = await fetchAdminPromptExport();
      const date = new Date().toISOString().slice(0, 10);
      downloadCsv(serializeAdminPromptCsv(rows), `deeper-together-prompts-${date}.csv`);
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setActiveAction(null);
    }
  }

  return (
    <details className="rounded-2xl border border-[var(--line)] bg-white p-5">
      <summary className="flex min-h-11 cursor-pointer items-center font-semibold text-[var(--accent-strong)]">CSV import and export</summary>
      <div className="border-t border-[var(--line)] pt-5">
        <p className="text-sm leading-6 text-[var(--muted)]">CSV columns: <code>prompt_text, level, category, tags, status</code>. Separate tag slugs with <code>|</code>. Imports are limited to 500 rows and skip duplicate prompt text.</p>
        <div className="mt-4 flex flex-wrap gap-2">
          <button type="button" onClick={() => downloadCsv(createAdminPromptCsvTemplate(categories, tags), "deeper-together-prompt-template.csv")} className="min-h-11 rounded-full border border-[var(--line)] px-4 text-sm font-semibold text-[var(--accent-strong)] hover:bg-[#f7f4ed]">Download template</button>
          <button type="button" onClick={() => void handleExport()} disabled={activeAction !== null} className="min-h-11 rounded-full border border-[var(--line)] px-4 text-sm font-semibold text-[var(--accent-strong)] hover:bg-[#f7f4ed] disabled:cursor-wait disabled:text-[var(--muted)]">{activeAction === "export" ? "Exporting..." : "Export all prompts"}</button>
        </div>

        <label className="mt-5 block text-sm font-semibold text-[var(--accent-strong)]">
          Choose CSV file
          <input ref={inputRef} type="file" accept=".csv,text/csv" onChange={(event) => void handleFile(event)} className="mt-2 block min-h-11 w-full rounded-xl border border-[var(--line)] bg-[#f7f4ed] px-3 py-2 text-sm font-normal file:mr-3 file:rounded-full file:border-0 file:bg-[var(--accent)] file:px-4 file:py-2 file:font-semibold file:text-white" />
        </label>

        {selectedFilename ? <p className="mt-3 text-sm text-[var(--muted)]">Selected: {selectedFilename}</p> : null}
        {pendingRows ? (
          <div className="mt-4 rounded-xl bg-[#edf4f0] p-4">
            <p className="text-sm font-semibold text-[var(--accent-strong)]">{pendingRows.length} validated {pendingRows.length === 1 ? "row" : "rows"} ready to import</p>
            <button type="button" onClick={() => void handleImport()} disabled={activeAction !== null} className="mt-3 min-h-11 rounded-full bg-[var(--accent)] px-5 text-sm font-semibold text-white hover:bg-[var(--accent-strong)] disabled:cursor-wait disabled:bg-[#8ca097]">{activeAction === "import" ? "Importing..." : "Import prompts"}</button>
          </div>
        ) : null}
        {result ? <p role="status" className="mt-4 rounded-xl bg-[#edf4f0] px-4 py-3 text-sm text-[var(--accent-strong)]">Imported {result.imported}; skipped {result.skipped} duplicate {result.skipped === 1 ? "row" : "rows"}.</p> : null}
        {errorMessage ? <p role="alert" className="mt-4 text-sm leading-6 text-[#7b3521]">{errorMessage}</p> : null}
      </div>
    </details>
  );
}
