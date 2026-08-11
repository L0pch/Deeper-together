"use client";

import { useState } from "react";

import { getGameErrorMessage } from "@/lib/game/errors";
import { saveAdminPrompt } from "@/lib/admin/prompt-service";
import type { AdminPrompt, AdminPromptCategory, AdminPromptTag } from "@/types/admin";
import type { PromptLevel } from "@/types/game";

type AdminPromptEditorProps = {
  categories: AdminPromptCategory[];
  editingPrompt: AdminPrompt | null;
  onCancelEdit: () => void;
  onSaved: (prompt: AdminPrompt) => Promise<void>;
  tags: AdminPromptTag[];
};

export function AdminPromptEditor({
  categories,
  editingPrompt,
  onCancelEdit,
  onSaved,
  tags,
}: AdminPromptEditorProps) {
  const activeCategories = categories.filter((category) => category.isActive);
  const [promptText, setPromptText] = useState(editingPrompt?.promptText ?? "");
  const [level, setLevel] = useState<PromptLevel>(editingPrompt?.level ?? 1);
  const [categoryId, setCategoryId] = useState(
    editingPrompt?.categoryId ?? activeCategories[0]?.id ?? "",
  );
  const [tagIds, setTagIds] = useState<string[]>(
    editingPrompt?.tags.map((tag) => tag.id) ?? [],
  );
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  function toggleTag(tagId: string) {
    setTagIds((current) => current.includes(tagId)
      ? current.filter((id) => id !== tagId)
      : [...current, tagId]);
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsSaving(true);
    setErrorMessage(null);
    try {
      const savedPrompt = await saveAdminPrompt({
        id: editingPrompt?.id,
        promptText,
        level,
        categoryId,
        tagIds,
      });
      await onSaved(savedPrompt);
      if (!editingPrompt) {
        setPromptText("");
        setLevel(1);
        setTagIds([]);
      }
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <section aria-labelledby="prompt-editor-heading" className="rounded-2xl border border-[#d8cbbb] bg-[#fffaf2] p-5 sm:p-6">
      <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--warm)]">
        {editingPrompt ? "Editing prompt" : "New prompt"}
      </p>
      <h2 id="prompt-editor-heading" className="mt-1 text-2xl font-semibold text-[var(--accent-strong)]">
        {editingPrompt ? "Update this card" : "Add a conversation card"}
      </h2>

      <form onSubmit={(event) => void handleSubmit(event)} className="mt-5 space-y-5">
        <label className="block text-sm font-semibold text-[var(--accent-strong)]">
          Prompt text
          <textarea
            value={promptText}
            onChange={(event) => setPromptText(event.target.value)}
            required
            maxLength={500}
            rows={5}
            className="mt-2 w-full resize-y rounded-xl border border-[var(--line)] bg-white px-4 py-3 font-normal leading-6 text-[var(--foreground)]"
          />
          <span className="mt-1 block text-right text-xs font-normal text-[var(--muted)]">{promptText.length}/500</span>
        </label>

        <div className="grid gap-4 sm:grid-cols-2">
          <label className="text-sm font-semibold text-[var(--accent-strong)]">
            Level
            <select value={level} onChange={(event) => setLevel(Number(event.target.value) as PromptLevel)} className="mt-2 min-h-12 w-full rounded-xl border border-[var(--line)] bg-white px-4 font-normal">
              <option value={1}>Level 1 · Light</option>
              <option value={2}>Level 2 · Reflective</option>
              <option value={3}>Level 3 · Deep</option>
            </select>
          </label>
          <label className="text-sm font-semibold text-[var(--accent-strong)]">
            Category
            <select value={categoryId} onChange={(event) => setCategoryId(event.target.value)} required className="mt-2 min-h-12 w-full rounded-xl border border-[var(--line)] bg-white px-4 font-normal">
              {activeCategories.map((category) => <option key={category.id} value={category.id}>{category.label}</option>)}
            </select>
          </label>
        </div>

        <fieldset>
          <legend className="text-sm font-semibold text-[var(--accent-strong)]">Tags</legend>
          <div className="mt-2 flex flex-wrap gap-2">
            {tags.map((tag) => (
              <label key={tag.id} className={`inline-flex min-h-11 items-center gap-2 rounded-full border px-4 text-sm ${tagIds.includes(tag.id) ? "border-[var(--accent)] bg-[#edf4f0] text-[var(--accent-strong)]" : "border-[var(--line)] bg-white text-[var(--muted)]"} ${!tag.isActive && !tagIds.includes(tag.id) ? "cursor-not-allowed opacity-55" : "cursor-pointer"}`}>
                <input type="checkbox" checked={tagIds.includes(tag.id)} disabled={!tag.isActive && !tagIds.includes(tag.id)} onChange={() => toggleTag(tag.id)} className="size-4 accent-[var(--accent)]" />
                {tag.name}{tag.isActive ? "" : " (inactive)"}
              </label>
            ))}
          </div>
        </fieldset>

        {errorMessage ? <p role="alert" className="text-sm leading-6 text-[#7b3521]">{errorMessage}</p> : null}

        <div className="grid gap-3 sm:grid-cols-2">
          <button type="submit" disabled={isSaving || !categoryId} className="min-h-12 rounded-full bg-[var(--accent)] px-5 font-semibold text-white hover:bg-[var(--accent-strong)] disabled:cursor-wait disabled:bg-[#8ca097]">
            {isSaving ? "Saving..." : editingPrompt ? "Save changes" : "Add prompt"}
          </button>
          {editingPrompt ? (
            <button type="button" onClick={onCancelEdit} disabled={isSaving} className="min-h-12 rounded-full border border-[var(--line)] px-5 font-semibold text-[var(--accent-strong)] hover:bg-white">
              Cancel editing
            </button>
          ) : null}
        </div>
      </form>
    </section>
  );
}
