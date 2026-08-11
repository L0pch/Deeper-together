"use client";

import { useEffect, useState } from "react";

import { AdminPromptEditor } from "@/components/admin-prompt-editor";
import { AdminImportExport } from "@/components/admin-import-export";
import { AdminTagManager } from "@/components/admin-tag-manager";
import { fetchAdminPromptCatalog, setAdminPromptState } from "@/lib/admin/prompt-service";
import { getGameErrorMessage } from "@/lib/game/errors";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type {
  AdminPrompt,
  AdminPromptCatalog,
  AdminPromptFilters,
  AdminPromptStateAction,
  AdminPromptStatus,
} from "@/types/admin";
import type { PromptLevel } from "@/types/game";

type AccessState = "loading" | "sign-in" | "unauthorized" | "ready";

const initialFilters: AdminPromptFilters = {
  search: "",
  level: null,
  categoryId: null,
  status: "all",
};

export function AdminClient() {
  const [accessState, setAccessState] = useState<AccessState>("loading");
  const [catalog, setCatalog] = useState<AdminPromptCatalog | null>(null);
  const [filters, setFilters] = useState<AdminPromptFilters>(initialFilters);
  const [draftFilters, setDraftFilters] = useState<AdminPromptFilters>(initialFilters);
  const [editingPrompt, setEditingPrompt] = useState<AdminPrompt | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isWorking, setIsWorking] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function loadCatalog(nextFilters: AdminPromptFilters) {
    const nextCatalog = await fetchAdminPromptCatalog(nextFilters);
    setCatalog(nextCatalog);
    setFilters(nextFilters);
    setAccessState("ready");
    setErrorMessage(null);
  }

  useEffect(() => {
    let cancelled = false;
    const supabase = getSupabaseBrowserClient();

    supabase.auth.getSession()
      .then(async ({ data, error }) => {
        if (error) throw error;
        if (!data.session?.user || data.session.user.is_anonymous) {
          if (!cancelled) setAccessState("sign-in");
          return;
        }
        try {
          const nextCatalog = await fetchAdminPromptCatalog(initialFilters);
          if (cancelled) return;
          setCatalog(nextCatalog);
          setAccessState("ready");
        } catch (catalogError) {
          if (cancelled) return;
          setErrorMessage(getGameErrorMessage(catalogError));
          setAccessState("unauthorized");
        }
      })
      .catch((error: unknown) => {
        if (cancelled) return;
        setErrorMessage(getGameErrorMessage(error));
        setAccessState("sign-in");
      });

    return () => { cancelled = true; };
  }, []);

  async function handleSignIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsWorking(true);
    setErrorMessage(null);
    const supabase = getSupabaseBrowserClient();
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (error) throw error;
      await loadCatalog(initialFilters);
      setPassword("");
    } catch (error) {
      const rawMessage = error instanceof Error ? error.message.toLowerCase() : "";
      setErrorMessage(rawMessage.includes("invalid login credentials")
        ? "The email or password was not recognized."
        : getGameErrorMessage(error));
      if (rawMessage.includes("admin_permission_required")) setAccessState("unauthorized");
    } finally {
      setIsWorking(false);
    }
  }

  async function handleSignOut() {
    setIsWorking(true);
    const supabase = getSupabaseBrowserClient();
    await supabase.auth.signOut();
    setCatalog(null);
    setEditingPrompt(null);
    setPassword("");
    setAccessState("sign-in");
    setIsWorking(false);
  }

  async function handleFilterSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsWorking(true);
    try {
      await loadCatalog(draftFilters);
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setIsWorking(false);
    }
  }

  async function refreshCatalog() {
    await loadCatalog(filters);
  }

  async function handlePromptState(prompt: AdminPrompt, action: AdminPromptStateAction) {
    if (action === "archive" && !window.confirm("Archive this prompt? It will stop appearing in future draws.")) return;
    setIsWorking(true);
    setErrorMessage(null);
    try {
      await setAdminPromptState(prompt.id, action);
      if (editingPrompt?.id === prompt.id) setEditingPrompt(null);
      await refreshCatalog();
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setIsWorking(false);
    }
  }

  if (accessState === "loading") {
    return <div role="status" className="py-10 text-center text-[var(--muted)]">Checking administrator access...</div>;
  }

  if (accessState === "sign-in") {
    return (
      <section aria-labelledby="admin-sign-in-heading" className="mx-auto max-w-md">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--warm)]">Administrators only</p>
        <h2 id="admin-sign-in-heading" className="mt-1 text-2xl font-semibold text-[var(--accent-strong)]">Sign in to manage prompts</h2>
        <p className="mt-2 text-sm leading-6 text-[var(--muted)]">Use a pre-authorized administrator account. Player guest sessions cannot access prompt content.</p>
        <form onSubmit={(event) => void handleSignIn(event)} className="mt-6 space-y-4">
          <label className="block text-sm font-semibold text-[var(--accent-strong)]">
            Email
            <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="username" className="mt-2 min-h-12 w-full rounded-xl border border-[var(--line)] bg-white px-4 font-normal" />
          </label>
          <label className="block text-sm font-semibold text-[var(--accent-strong)]">
            Password
            <input type="password" value={password} onChange={(event) => setPassword(event.target.value)} required autoComplete="current-password" className="mt-2 min-h-12 w-full rounded-xl border border-[var(--line)] bg-white px-4 font-normal" />
          </label>
          {errorMessage ? <p role="alert" className="text-sm leading-6 text-[#7b3521]">{errorMessage}</p> : null}
          <button type="submit" disabled={isWorking} className="min-h-12 w-full rounded-full bg-[var(--accent)] px-5 font-semibold text-white hover:bg-[var(--accent-strong)] disabled:cursor-wait disabled:bg-[#8ca097]">
            {isWorking ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </section>
    );
  }

  if (accessState === "unauthorized") {
    return (
      <div className="space-y-5 text-center">
        <p role="alert" className="rounded-xl border border-[#e2b9aa] bg-[#fff3ee] px-4 py-3 text-sm leading-6 text-[#7b3521]">{errorMessage}</p>
        <button type="button" onClick={() => void handleSignOut()} disabled={isWorking} className="min-h-12 rounded-full border border-[var(--line)] px-6 font-semibold text-[var(--accent-strong)] hover:bg-[#f4f1e9]">Sign out</button>
      </div>
    );
  }

  if (!catalog) return null;

  return (
    <div className="space-y-7">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm text-[var(--muted)]">{catalog.total} {catalog.total === 1 ? "prompt" : "prompts"} match the current view</p>
          <p className="mt-1 text-xs text-[var(--muted)]">Only active, unarchived prompts are eligible for future game draws.</p>
        </div>
        <button type="button" onClick={() => void handleSignOut()} disabled={isWorking} className="min-h-11 rounded-full px-4 text-sm font-semibold text-[var(--accent)] hover:bg-[#edf4f0]">Sign out</button>
      </div>

      {errorMessage ? <p role="alert" className="rounded-xl border border-[#e2b9aa] bg-[#fff3ee] px-4 py-3 text-sm leading-6 text-[#7b3521]">{errorMessage}</p> : null}

      <AdminPromptEditor
        key={editingPrompt?.id ?? "new-prompt"}
        categories={catalog.categories}
        editingPrompt={editingPrompt}
        onCancelEdit={() => setEditingPrompt(null)}
        onSaved={async () => {
          setEditingPrompt(null);
          await refreshCatalog();
        }}
        tags={catalog.tags}
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <AdminTagManager onChanged={refreshCatalog} tags={catalog.tags} />
        <AdminImportExport
          categories={catalog.categories}
          onImported={refreshCatalog}
          tags={catalog.tags}
        />
      </div>

      <section aria-labelledby="prompt-library-heading">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--warm)]">Prompt library</p>
        <h2 id="prompt-library-heading" className="mt-1 text-2xl font-semibold text-[var(--accent-strong)]">Find and manage cards</h2>

        <form onSubmit={(event) => void handleFilterSubmit(event)} className="mt-4 grid gap-3 rounded-2xl border border-[var(--line)] bg-white p-4 sm:grid-cols-2 lg:grid-cols-5">
          <label className="text-xs font-semibold text-[var(--muted)] lg:col-span-2">
            Search
            <input value={draftFilters.search} onChange={(event) => setDraftFilters((current) => ({ ...current, search: event.target.value }))} maxLength={100} placeholder="Search prompt text" className="mt-1 min-h-11 w-full rounded-xl border border-[var(--line)] px-3 text-sm font-normal text-[var(--foreground)]" />
          </label>
          <label className="text-xs font-semibold text-[var(--muted)]">
            Level
            <select value={draftFilters.level ?? ""} onChange={(event) => setDraftFilters((current) => ({ ...current, level: event.target.value ? Number(event.target.value) as PromptLevel : null }))} className="mt-1 min-h-11 w-full rounded-xl border border-[var(--line)] px-3 text-sm font-normal text-[var(--foreground)]">
              <option value="">All levels</option>
              <option value="1">Level 1</option><option value="2">Level 2</option><option value="3">Level 3</option>
            </select>
          </label>
          <label className="text-xs font-semibold text-[var(--muted)]">
            Category
            <select value={draftFilters.categoryId ?? ""} onChange={(event) => setDraftFilters((current) => ({ ...current, categoryId: event.target.value || null }))} className="mt-1 min-h-11 w-full rounded-xl border border-[var(--line)] px-3 text-sm font-normal text-[var(--foreground)]">
              <option value="">All categories</option>
              {catalog.categories.map((category) => <option key={category.id} value={category.id}>{category.label}</option>)}
            </select>
          </label>
          <label className="text-xs font-semibold text-[var(--muted)]">
            Status
            <select value={draftFilters.status} onChange={(event) => setDraftFilters((current) => ({ ...current, status: event.target.value as AdminPromptStatus }))} className="mt-1 min-h-11 w-full rounded-xl border border-[var(--line)] px-3 text-sm font-normal text-[var(--foreground)]">
              <option value="all">All statuses</option><option value="active">Active</option><option value="inactive">Inactive</option><option value="archived">Archived</option>
            </select>
          </label>
          <button type="submit" disabled={isWorking} className="min-h-11 rounded-full bg-[var(--accent)] px-4 text-sm font-semibold text-white hover:bg-[var(--accent-strong)] disabled:cursor-wait disabled:bg-[#8ca097] sm:col-span-2 lg:col-span-5">{isWorking ? "Loading..." : "Apply filters"}</button>
        </form>

        {catalog.prompts.length ? (
          <ol className="mt-4 space-y-3">
            {catalog.prompts.map((prompt) => {
              const statusLabel = prompt.archivedAt ? "Archived" : prompt.isActive ? "Active" : "Inactive";
              return (
                <li key={prompt.id} className="rounded-2xl border border-[var(--line)] bg-white p-5">
                  <div className="flex flex-wrap items-center gap-2 text-xs font-semibold">
                    <span className="rounded-full bg-[#edf4f0] px-3 py-1 text-[var(--accent-strong)]">Level {prompt.level}</span>
                    <span className="rounded-full bg-[#f2eee5] px-3 py-1 text-[var(--muted)]">{prompt.categoryLabel}</span>
                    <span className={`rounded-full px-3 py-1 ${prompt.isActive && !prompt.archivedAt ? "bg-[#dfeee5] text-[#285d43]" : "bg-[#f5e2d9] text-[#7b452f]"}`}>{statusLabel}</span>
                  </div>
                  <p className="mt-3 text-base font-semibold leading-7 text-[var(--accent-strong)]">{prompt.promptText}</p>
                  {prompt.tags.length ? <p className="mt-2 text-sm text-[var(--muted)]">{prompt.tags.map((tag) => `#${tag.slug}`).join(" · ")}</p> : null}
                  <div className="mt-4 flex flex-wrap gap-2">
                    <button type="button" onClick={() => setEditingPrompt(prompt)} disabled={isWorking} className="min-h-11 rounded-full border border-[var(--line)] px-4 text-sm font-semibold text-[var(--accent-strong)] hover:bg-[#f7f4ed]">Edit</button>
                    {prompt.archivedAt ? (
                      <button type="button" onClick={() => void handlePromptState(prompt, "restore")} disabled={isWorking} className="min-h-11 rounded-full border border-[var(--line)] px-4 text-sm font-semibold text-[var(--accent-strong)] hover:bg-[#f7f4ed]">Restore as inactive</button>
                    ) : (
                      <>
                        <button type="button" onClick={() => void handlePromptState(prompt, prompt.isActive ? "deactivate" : "activate")} disabled={isWorking} className="min-h-11 rounded-full border border-[var(--line)] px-4 text-sm font-semibold text-[var(--accent-strong)] hover:bg-[#f7f4ed]">{prompt.isActive ? "Deactivate" : "Activate"}</button>
                        <button type="button" onClick={() => void handlePromptState(prompt, "archive")} disabled={isWorking} className="min-h-11 rounded-full border border-[#d6a99a] px-4 text-sm font-semibold text-[#8a3d2a] hover:bg-[#fff0eb]">Archive</button>
                      </>
                    )}
                  </div>
                </li>
              );
            })}
          </ol>
        ) : <p className="mt-5 rounded-xl border border-[var(--line)] bg-white px-4 py-6 text-center text-sm text-[var(--muted)]">No prompts match these filters.</p>}
      </section>
    </div>
  );
}
