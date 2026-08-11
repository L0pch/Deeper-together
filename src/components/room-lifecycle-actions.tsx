"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { getGameErrorMessage } from "@/lib/game/errors";
import { closeRoom, leaveRoom } from "@/lib/game/room-service";

type RoomLifecycleActionsProps = {
  isHost: boolean;
  roomId: string;
};

export function RoomLifecycleActions({ isHost, roomId }: RoomLifecycleActionsProps) {
  const router = useRouter();
  const [activeAction, setActiveAction] = useState<"leave" | "close" | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleLeave() {
    if (!window.confirm(isHost
      ? "Leave this room? Host status will pass to the next player."
      : "Leave this room?")) return;

    setActiveAction("leave");
    setErrorMessage(null);
    try {
      await leaveRoom(roomId);
      router.replace("/");
      router.refresh();
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
      setActiveAction(null);
    }
  }

  async function handleClose() {
    if (!window.confirm("Close this room for everyone? Prompt history will be retained only until normal room expiry.")) return;

    setActiveAction("close");
    setErrorMessage(null);
    try {
      await closeRoom(roomId);
      router.replace("/");
      router.refresh();
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
      setActiveAction(null);
    }
  }

  return (
    <details className="rounded-2xl border border-[var(--line)] bg-white px-5 py-3">
      <summary className="flex min-h-11 cursor-pointer items-center font-semibold text-[var(--accent-strong)]">
        Room options
      </summary>
      <div className="grid gap-3 border-t border-[var(--line)] pt-4 sm:grid-cols-2">
        <button type="button" onClick={() => void handleLeave()} disabled={activeAction !== null} className="min-h-12 rounded-full border border-[#b8aa98] px-5 font-semibold text-[var(--accent-strong)] hover:bg-[#f7f2e9] disabled:cursor-wait disabled:text-[var(--muted)]">
          {activeAction === "leave" ? "Leaving..." : "Leave room"}
        </button>
        {isHost ? (
          <button type="button" onClick={() => void handleClose()} disabled={activeAction !== null} className="min-h-12 rounded-full border border-[#d6a99a] px-5 font-semibold text-[#8a3d2a] hover:bg-[#fff0eb] disabled:cursor-wait disabled:text-[var(--muted)]">
            {activeAction === "close" ? "Closing..." : "Close room for everyone"}
          </button>
        ) : null}
      </div>
      {errorMessage ? <p role="alert" className="mt-3 text-sm leading-6 text-[#7b3521]">{errorMessage}</p> : null}
    </details>
  );
}
