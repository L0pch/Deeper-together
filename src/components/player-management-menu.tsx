"use client";

import { useRef, useState } from "react";

import { getGameErrorMessage } from "@/lib/game/errors";
import { kickRoomPlayer, makeRoomHost, playRoomPlayerNow } from "@/lib/game/room-service";
import type { RoomPlayerSnapshot, RoomSnapshot } from "@/types/game";

type PlayerManagementMenuProps = {
  inline?: boolean;
  player: RoomPlayerSnapshot;
  snapshot: RoomSnapshot;
  replaceSnapshot: (snapshot: RoomSnapshot) => void;
};

type PlayerAction = "kick" | "host" | "play";

const confirmationMessages: Record<PlayerAction, (name: string) => string> = {
  kick: (name) => `Remove ${name} from this room?`,
  host: (name) => `Make ${name} the new host? You will immediately lose host controls.`,
  play: (name) => `End the current turn and let ${name} play now?`,
};

export function PlayerManagementMenu({
  player,
  snapshot,
  replaceSnapshot,
  inline = false,
}: PlayerManagementMenuProps) {
  const detailsRef = useRef<HTMLDetailsElement>(null);
  const [activeAction, setActiveAction] = useState<PlayerAction | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const canPlayNow = snapshot.room.status === "active"
    && snapshot.currentTurn !== null
    && snapshot.currentTurn.playerId !== player.id;

  async function runAction(action: PlayerAction) {
    if (!window.confirm(confirmationMessages[action](player.displayName))) return;

    setActiveAction(action);
    setErrorMessage(null);
    try {
      if (action === "kick") {
        replaceSnapshot(await kickRoomPlayer(snapshot.room.id, player.id));
      } else if (action === "host") {
        replaceSnapshot(await makeRoomHost(snapshot.room.id, player.id));
      } else if (snapshot.currentTurn) {
        replaceSnapshot(await playRoomPlayerNow(
          snapshot.room.id,
          player.id,
          snapshot.currentTurn.id,
        ));
      }
      if (detailsRef.current) detailsRef.current.open = false;
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setActiveAction(null);
    }
  }

  return (
    <details ref={detailsRef} className={inline ? "mt-2" : "relative shrink-0"}>
      <summary
        aria-label={`Manage ${player.displayName}`}
        className="grid min-h-11 min-w-11 cursor-pointer list-none place-items-center rounded-full text-xl font-bold leading-none text-[var(--muted)] hover:bg-[#f2eee5] [&::-webkit-details-marker]:hidden"
      >
        <span aria-hidden="true">⋯</span>
      </summary>
      <div className={`${inline ? "mt-1 w-full" : "absolute right-0 z-20 mt-1 w-48"} space-y-1 rounded-xl border border-[var(--line)] bg-white p-2 text-sm shadow-xl`}>
        {canPlayNow ? (
          <button type="button" onClick={() => void runAction("play")} disabled={activeAction !== null} className="min-h-11 w-full rounded-lg px-3 text-left font-semibold text-[var(--accent-strong)] hover:bg-[#edf4f0] disabled:cursor-wait disabled:text-[var(--muted)]">
            {activeAction === "play" ? "Moving..." : "Play now"}
          </button>
        ) : null}
        <button type="button" onClick={() => void runAction("host")} disabled={activeAction !== null} className="min-h-11 w-full rounded-lg px-3 text-left font-semibold text-[var(--accent-strong)] hover:bg-[#edf4f0] disabled:cursor-wait disabled:text-[var(--muted)]">
          {activeAction === "host" ? "Transferring..." : "Make host"}
        </button>
        <button type="button" onClick={() => void runAction("kick")} disabled={activeAction !== null} className="min-h-11 w-full rounded-lg px-3 text-left font-semibold text-[#8a3d2a] hover:bg-[#fff0eb] disabled:cursor-wait disabled:text-[var(--muted)]">
          {activeAction === "kick" ? "Removing..." : "Kick player"}
        </button>
        {errorMessage ? <p role="alert" className="px-3 py-2 text-xs leading-5 text-[#7b3521]">{errorMessage}</p> : null}
      </div>
    </details>
  );
}
