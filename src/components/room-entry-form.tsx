"use client";

import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";

import { PromptLevelPicker } from "@/components/prompt-level-picker";
import { ensureAnonymousUser } from "@/lib/auth/anonymous-session";
import { getGameErrorMessage } from "@/lib/game/errors";
import { parseRoomSnapshot } from "@/lib/game/snapshot";
import { DISPLAY_NAME_MAX_LENGTH, getDisplayNameError, getRoomCodeError, normaliseDisplayName, normaliseRoomCode } from "@/lib/game/validation";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type { PromptLevel } from "@/types/game";

type RoomEntryFormProps =
  | { mode: "create"; defaultRoomCode?: never }
  | { mode: "join"; defaultRoomCode?: string };

export function RoomEntryForm({ mode, defaultRoomCode = "" }: RoomEntryFormProps) {
  const router = useRouter();
  const [displayName, setDisplayName] = useState("");
  const [roomCode, setRoomCode] = useState(normaliseRoomCode(defaultRoomCode));
  const [promptLevel, setPromptLevel] = useState<PromptLevel>(1);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErrorMessage(null);

    const displayNameError = getDisplayNameError(displayName);
    const roomCodeError = mode === "join" ? getRoomCodeError(roomCode) : null;
    if (displayNameError || roomCodeError) {
      setErrorMessage(displayNameError ?? roomCodeError);
      return;
    }

    setIsSubmitting(true);
    try {
      const supabase = getSupabaseBrowserClient();
      await ensureAnonymousUser(supabase);
      const result = mode === "create"
        ? await supabase.rpc("create_room", { p_display_name: normaliseDisplayName(displayName), p_selected_level: promptLevel })
        : await supabase.rpc("join_room", { p_display_name: normaliseDisplayName(displayName), p_room_code: normaliseRoomCode(roomCode), p_selected_level: promptLevel });

      if (result.error) throw result.error;
      const snapshot = parseRoomSnapshot(result.data);
      router.push(`/room/${encodeURIComponent(snapshot.room.code)}/lobby`);
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
      setIsSubmitting(false);
    }
  }

  const actionLabel = mode === "create" ? "Create room" : "Join room";

  return (
    <form onSubmit={handleSubmit} noValidate className="space-y-6">
      {mode === "join" ? (
        <label className="block">
          <span className="mb-2 block text-sm font-semibold text-[var(--accent-strong)]">Room code</span>
          <input value={roomCode} onChange={(event) => setRoomCode(normaliseRoomCode(event.target.value).slice(0, 6))} disabled={isSubmitting} autoComplete="off" autoCapitalize="characters" maxLength={6} placeholder="ABC234" aria-describedby={errorMessage ? "room-entry-error" : undefined} className="min-h-12 w-full rounded-xl border border-[var(--line)] bg-white px-4 font-semibold uppercase tracking-[0.18em] text-[var(--foreground)] placeholder:text-[#9aa29e]" />
        </label>
      ) : null}

      <label className="block">
        <span className="mb-2 block text-sm font-semibold text-[var(--accent-strong)]">Your display name</span>
        <input value={displayName} onChange={(event) => setDisplayName(event.target.value)} disabled={isSubmitting} autoComplete="nickname" maxLength={DISPLAY_NAME_MAX_LENGTH} placeholder="e.g. Jordan" aria-describedby={errorMessage ? "room-entry-error" : undefined} className="min-h-12 w-full rounded-xl border border-[var(--line)] bg-white px-4 text-[var(--foreground)] placeholder:text-[#9aa29e]" />
      </label>

      <PromptLevelPicker value={promptLevel} onChange={setPromptLevel} disabled={isSubmitting} />

      {errorMessage ? (
        <p id="room-entry-error" role="alert" className="rounded-xl border border-[#e2b9aa] bg-[#fff3ee] px-4 py-3 text-sm leading-6 text-[#7b3521]">{errorMessage}</p>
      ) : null}

      <button type="submit" disabled={isSubmitting} className="min-h-12 w-full rounded-full bg-[var(--accent)] px-6 font-semibold text-white transition-colors hover:bg-[var(--accent-strong)] disabled:cursor-wait disabled:bg-[#8ca097]">
        {isSubmitting ? `${actionLabel}...` : actionLabel}
      </button>

      <p className="text-center text-xs leading-5 text-[var(--muted)]">
        {mode === "join" ? "Tabs in the same browser share one guest player. Use a private window or another browser profile to test a second player." : "No email or password is needed. A private guest session keeps your place when you refresh on this browser."}
      </p>
    </form>
  );
}
