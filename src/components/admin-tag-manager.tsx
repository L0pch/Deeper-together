"use client";

import { useState } from "react";

import { saveAdminTag, setAdminTagActive } from "@/lib/admin/prompt-service";
import { normaliseTagSlug } from "@/lib/admin/prompt-csv";
import { getGameErrorMessage } from "@/lib/game/errors";
import type { AdminPromptTag } from "@/types/admin";

type AdminTagManagerProps = {
  onChanged: () => Promise<void>;
  tags: AdminPromptTag[];
};

export function AdminTagManager({ onChanged, tags }: AdminTagManagerProps) {
  const [editingTag, setEditingTag] = useState<AdminPromptTag | null>(null);
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [slugWasEdited, setSlugWasEdited] = useState(false);
  const [isWorking, setIsWorking] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  function beginEdit(tag: AdminPromptTag) {
    setEditingTag(tag);
    setName(tag.name);
    setSlug(tag.slug);
    setSlugWasEdited(true);
    setErrorMessage(null);
  }

  function resetForm() {
    setEditingTag(null);
    setName("");
    setSlug("");
    setSlugWasEdited(false);
  }

  async function handleSave(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsWorking(true);
    setErrorMessage(null);
    try {
      await saveAdminTag({ id: editingTag?.id, name, slug });
      resetForm();
      await onChanged();
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setIsWorking(false);
    }
  }

  async function handleState(tag: AdminPromptTag) {
    setIsWorking(true);
    setErrorMessage(null);
    try {
      await setAdminTagActive(tag.id, !tag.isActive);
      await onChanged();
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setIsWorking(false);
    }
  }

  return (
    <details className="rounded-2xl border border-[var(--line)] bg-white p-5">
      <summary className="flex min-h-11 cursor-pointer items-center font-semibold text-[var(--accent-strong)]">
        Tag vocabulary ({tags.filter((tag) => tag.isActive).length} active)
      </summary>
      <div className="border-t border-[var(--line)] pt-5">
        <p className="text-sm leading-6 text-[var(--muted)]">Inactive tags remain on existing prompts and historical draws, but cannot be assigned by CSV imports.</p>
        <form onSubmit={(event) => void handleSave(event)} className="mt-4 grid gap-3 sm:grid-cols-2">
          <label className="text-sm font-semibold text-[var(--accent-strong)]">
            Tag name
            <input value={name} onChange={(event) => {
              const nextName = event.target.value;
              setName(nextName);
              if (!slugWasEdited) setSlug(normaliseTagSlug(nextName));
            }} required maxLength={40} className="mt-1 min-h-11 w-full rounded-xl border border-[var(--line)] px-3 font-normal" />
          </label>
          <label className="text-sm font-semibold text-[var(--accent-strong)]">
            Slug
            <input value={slug} onChange={(event) => { setSlug(normaliseTagSlug(event.target.value)); setSlugWasEdited(true); }} required maxLength={48} pattern="[a-z0-9]+(?:-[a-z0-9]+)*" className="mt-1 min-h-11 w-full rounded-xl border border-[var(--line)] px-3 font-normal" />
          </label>
          <button type="submit" disabled={isWorking} className="min-h-11 rounded-full bg-[var(--accent)] px-4 text-sm font-semibold text-white hover:bg-[var(--accent-strong)] disabled:cursor-wait disabled:bg-[#8ca097]">
            {isWorking ? "Saving..." : editingTag ? "Save tag changes" : "Add tag"}
          </button>
          {editingTag ? <button type="button" onClick={resetForm} disabled={isWorking} className="min-h-11 rounded-full border border-[var(--line)] px-4 text-sm font-semibold text-[var(--accent-strong)]">Cancel tag editing</button> : null}
        </form>

        {errorMessage ? <p role="alert" className="mt-3 text-sm leading-6 text-[#7b3521]">{errorMessage}</p> : null}

        <ul className="mt-5 grid gap-2 sm:grid-cols-2">
          {tags.map((tag) => (
            <li key={tag.id} className="flex items-center gap-2 rounded-xl bg-[#f7f4ed] px-3 py-2">
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold text-[var(--accent-strong)]">{tag.name}</p>
                <p className="truncate text-xs text-[var(--muted)]">#{tag.slug} · {tag.isActive ? "Active" : "Inactive"}</p>
              </div>
              <button type="button" onClick={() => beginEdit(tag)} disabled={isWorking} aria-label={`Edit ${tag.name} tag`} className="min-h-11 rounded-full px-3 text-xs font-semibold text-[var(--accent)] hover:bg-white">Edit</button>
              <button type="button" onClick={() => void handleState(tag)} disabled={isWorking} aria-label={`${tag.isActive ? "Deactivate" : "Activate"} ${tag.name} tag`} className="min-h-11 rounded-full px-3 text-xs font-semibold text-[var(--accent)] hover:bg-white">{tag.isActive ? "Off" : "On"}</button>
            </li>
          ))}
        </ul>
      </div>
    </details>
  );
}
