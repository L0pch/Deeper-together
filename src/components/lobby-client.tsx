"use client";

import Link from "next/link";
import { useState } from "react";

import { PlayerManagementMenu } from "@/components/player-management-menu";
import { RoomLifecycleActions } from "@/components/room-lifecycle-actions";
import { useRoomSnapshot, type RealtimeConnectionState } from "@/hooks/use-room-snapshot";
import { getGameErrorMessage } from "@/lib/game/errors";
import { setRoomLocked, startRoomGame } from "@/lib/game/room-service";
import { normaliseRoomCode } from "@/lib/game/validation";

type LobbyClientProps = { roomCode: string };

const levelLabels = {
  1: "Level 1",
  2: "Level 2",
  3: "Level 3",
} as const;

const connectionLabels: Record<RealtimeConnectionState, string> = {
  connecting: "Connecting live updates",
  connected: "Live updates connected",
  reconnecting: "Reconnecting live updates",
  disconnected: "Live updates disconnected",
};

export function LobbyClient({ roomCode }: LobbyClientProps) {
  const code = normaliseRoomCode(roomCode);
  const {
    connectionState,
    currentUserId,
    errorMessage,
    isLoading,
    isRefreshing,
    refresh,
    replaceSnapshot,
    snapshot,
  } = useRoomSnapshot(code);
  const [hasCopied, setHasCopied] = useState(false);
  const [hostAction, setHostAction] = useState<"start" | "lock" | null>(null);
  const [hostActionError, setHostActionError] = useState<string | null>(null);

  async function handleLockChange() {
    if (!snapshot) return;
    setHostAction("lock");
    setHostActionError(null);
    try {
      replaceSnapshot(await setRoomLocked(snapshot.room.id, !snapshot.room.isLocked));
    } catch (error) {
      setHostActionError(getGameErrorMessage(error));
    } finally {
      setHostAction(null);
    }
  }

  async function handleStartGame() {
    if (!snapshot) return;
    setHostAction("start");
    setHostActionError(null);
    try {
      replaceSnapshot(await startRoomGame(snapshot.room.id));
    } catch (error) {
      setHostActionError(getGameErrorMessage(error));
    } finally {
      setHostAction(null);
    }
  }

  async function copyRoomCode() {
    let copied = false;
    try {
      if (!navigator.clipboard?.writeText) throw new Error("clipboard_unavailable");
      await navigator.clipboard.writeText(code);
      copied = true;
    } catch {
      const input = document.createElement("textarea");
      input.value = code;
      input.setAttribute("readonly", "");
      input.style.position = "fixed";
      input.style.opacity = "0";
      document.body.append(input);
      input.select();
      copied = document.execCommand("copy");
      input.remove();
    }

    if (!copied) {
      window.prompt("Copy this room code:", code);
      return;
    }

    setHasCopied(true);
    window.setTimeout(() => setHasCopied(false), 1800);
  }

  if (isLoading && !snapshot) {
    return (
      <div role="status" className="py-10 text-center text-[var(--muted)]">
        Loading the room...
      </div>
    );
  }

  if (!snapshot) {
    return (
      <div className="space-y-5">
        <p role="alert" className="rounded-xl border border-[#e2b9aa] bg-[#fff3ee] px-4 py-3 text-sm leading-6 text-[#7b3521]">
          {errorMessage ?? "That room could not be loaded."}
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          <Link href={`/join?code=${encodeURIComponent(code)}`} className="inline-flex min-h-12 items-center justify-center rounded-full bg-[var(--accent)] px-5 font-semibold text-white hover:bg-[var(--accent-strong)]">
            Join this room
          </Link>
          <button type="button" onClick={() => void refresh()} className="min-h-12 rounded-full border border-[var(--line)] px-5 font-semibold text-[var(--accent-strong)] hover:bg-[#f4f1e9]">
            Try again
          </button>
        </div>
      </div>
    );
  }

  const currentPlayer = snapshot.currentTurn
    ? snapshot.players.find((player) => player.id === snapshot.currentTurn?.playerId)
    : null;
  const isHost = snapshot.room.hostUserId === currentUserId;

  return (
    <div className="space-y-7">
      <section className="rounded-2xl bg-[#edf4f0] p-5 sm:flex sm:items-center sm:justify-between sm:gap-5">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--muted)]">Room code</p>
          <p className="mt-1 text-3xl font-semibold tracking-[0.16em] text-[var(--accent-strong)]">{snapshot.room.code}</p>
        </div>
        <button type="button" onClick={() => void copyRoomCode()} className="mt-4 min-h-11 rounded-full border border-[#aec0b7] bg-white px-5 text-sm font-semibold text-[var(--accent-strong)] hover:bg-[#f8fbf9] sm:mt-0" aria-live="polite">
          {hasCopied ? "Copied" : "Copy code"}
        </button>
      </section>

      <div className="flex flex-wrap gap-2 text-sm">
        <span className="rounded-full bg-[#f2eee5] px-3 py-1.5 font-medium text-[var(--muted)]">
          {snapshot.players.length} of {snapshot.room.maxPlayers} players
        </span>
        <span className="rounded-full bg-[#f2eee5] px-3 py-1.5 font-medium capitalize text-[var(--muted)]">
          {snapshot.room.status}
        </span>
        <span className="rounded-full bg-[#f2eee5] px-3 py-1.5 font-medium text-[var(--muted)]">
          {snapshot.room.isLocked ? "Room locked" : "Room open"}
        </span>
        <span className="inline-flex items-center gap-2 rounded-full bg-[#f2eee5] px-3 py-1.5 font-medium text-[var(--muted)]">
          <span aria-hidden="true" className={`size-2 rounded-full ${connectionState === "connected" ? "bg-[#3f7a5f]" : "bg-[#b47c54]"}`} />
          {connectionLabels[connectionState]}
        </span>
      </div>

      {errorMessage ? (
        <p role="alert" className="rounded-xl border border-[#e2b9aa] bg-[#fff3ee] px-4 py-3 text-sm leading-6 text-[#7b3521]">
          {errorMessage} The last confirmed room state is still shown.
        </p>
      ) : null}

      {isHost ? (
        <section aria-labelledby="host-controls-heading" className="rounded-2xl border border-[#d8cbbb] bg-[#fffaf2] p-5">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--warm)]">Host only</p>
          <h2 id="host-controls-heading" className="mt-1 text-xl font-semibold text-[var(--accent-strong)]">Room controls</h2>
          <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
            Locking prevents new players from joining. Current players stay in the room.
          </p>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            {snapshot.room.status === "lobby" ? (
              <button type="button" onClick={() => void handleStartGame()} disabled={hostAction !== null} className="min-h-12 rounded-full bg-[var(--accent)] px-5 font-semibold text-white hover:bg-[var(--accent-strong)] disabled:cursor-wait disabled:bg-[#8ca097]">
                {hostAction === "start" ? "Starting..." : "Start game"}
              </button>
            ) : (
              <div className="flex min-h-12 items-center justify-center rounded-full bg-[#e6efe9] px-5 text-sm font-semibold text-[var(--accent-strong)]">
                Game started
              </div>
            )}
            <button type="button" onClick={() => void handleLockChange()} disabled={hostAction !== null} className="min-h-12 rounded-full border border-[#b8aa98] bg-white px-5 font-semibold text-[var(--accent-strong)] hover:bg-[#f7f2e9] disabled:cursor-wait disabled:text-[var(--muted)]">
              {hostAction === "lock" ? "Saving..." : snapshot.room.isLocked ? "Unlock room" : "Lock room"}
            </button>
          </div>
          {hostActionError ? (
            <p role="alert" className="mt-4 text-sm leading-6 text-[#7b3521]">{hostActionError}</p>
          ) : null}
        </section>
      ) : null}

      {currentPlayer ? (
        <p className="rounded-xl border border-[var(--line)] bg-[#fffaf2] px-4 py-3 text-sm text-[var(--muted)]">
          Current player: <strong className="text-[var(--accent-strong)]">{currentPlayer.displayName}</strong>
        </p>
      ) : (
        <p className="rounded-xl border border-[var(--line)] bg-[#fffaf2] px-4 py-3 text-sm text-[var(--muted)]">
          The game has not started yet. Share the room code while everyone gathers.
        </p>
      )}

      {snapshot.room.status === "active" ? (
        <Link href={`/room/${encodeURIComponent(code)}/game`} className="inline-flex min-h-12 w-full items-center justify-center rounded-full bg-[var(--accent)] px-6 font-semibold text-white hover:bg-[var(--accent-strong)]">
          Enter game
        </Link>
      ) : null}

      <section aria-labelledby="player-list-heading">
        <div className="flex items-end justify-between gap-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[var(--warm)]">Queue order</p>
            <h2 id="player-list-heading" className="mt-1 text-2xl font-semibold text-[var(--accent-strong)]">Players</h2>
          </div>
          <button type="button" onClick={() => void refresh()} disabled={isRefreshing} className="min-h-11 rounded-full px-4 text-sm font-semibold text-[var(--accent)] hover:bg-[#edf4f0] disabled:cursor-wait disabled:text-[var(--muted)]">
            {isRefreshing ? "Refreshing..." : "Refresh"}
          </button>
        </div>

        <ol className="mt-4 space-y-3">
          {snapshot.players.map((player, index) => (
            <li key={player.id} className="flex min-h-16 items-center gap-3 rounded-xl border border-[var(--line)] bg-white px-4 py-3">
              <span aria-hidden="true" className="grid size-9 shrink-0 place-items-center rounded-full bg-[var(--accent)] text-sm font-semibold text-white">
                {player.displayName.slice(0, 1).toUpperCase()}
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate font-semibold text-[var(--accent-strong)]">
                  <span className="mr-2 text-sm font-normal text-[var(--muted)]">{index + 1}.</span>
                  {player.displayName}
                  {player.userId === currentUserId ? <span className="font-normal text-[var(--muted)]"> (you)</span> : null}
                </p>
                <p className="mt-0.5 text-sm text-[var(--muted)]">{levelLabels[player.selectedLevel]}</p>
              </div>
              {player.isHost ? (
                <span className="rounded-full bg-[#f5e2d9] px-3 py-1 text-xs font-semibold text-[#7b452f]">Host</span>
              ) : null}
              {isHost && player.userId !== currentUserId ? (
                <PlayerManagementMenu
                  player={player}
                  snapshot={snapshot}
                  replaceSnapshot={replaceSnapshot}
                />
              ) : null}
            </li>
          ))}
        </ol>
      </section>

      <RoomLifecycleActions isHost={isHost} roomId={snapshot.room.id} />

      <p className="text-center text-xs leading-5 text-[var(--muted)]">
        Realtime events prompt a fresh authoritative snapshot. Manual refresh is always available if a connection is interrupted.
      </p>
    </div>
  );
}
