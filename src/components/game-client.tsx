"use client";

import Link from "next/link";

import { PlayerManagementMenu } from "@/components/player-management-menu";
import { RoomLifecycleActions } from "@/components/room-lifecycle-actions";
import { TurnControls } from "@/components/turn-controls";
import { useRoomSnapshot, type RealtimeConnectionState } from "@/hooks/use-room-snapshot";
import { normaliseRoomCode } from "@/lib/game/validation";

type GameClientProps = { roomCode: string };

const connectionLabels: Record<RealtimeConnectionState, string> = {
  connecting: "Connecting",
  connected: "Live",
  reconnecting: "Reconnecting",
  disconnected: "Disconnected",
};

const outcomeLabels = {
  current: "Current card",
  redrawn: "Redrawn",
  answered: "Answered",
  skipped: "Skipped",
} as const;

export function GameClient({ roomCode }: GameClientProps) {
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

  if (isLoading && !snapshot) {
    return <div role="status" className="py-12 text-center text-[var(--muted)]">Loading the game...</div>;
  }

  if (!snapshot) {
    return (
      <div className="space-y-5">
        <p role="alert" className="rounded-xl border border-[#e2b9aa] bg-[#fff3ee] px-4 py-3 text-sm leading-6 text-[#7b3521]">{errorMessage ?? "That game could not be loaded."}</p>
        <Link href={`/join?code=${encodeURIComponent(code)}`} className="inline-flex min-h-12 w-full items-center justify-center rounded-full bg-[var(--accent)] px-5 font-semibold text-white hover:bg-[var(--accent-strong)]">Join this room</Link>
      </div>
    );
  }

  if (snapshot.room.status === "lobby" || !snapshot.currentTurn) {
    return (
      <div className="space-y-5 text-center">
        <p className="text-[var(--muted)]">The game has not started yet.</p>
        <Link href={`/room/${encodeURIComponent(code)}/lobby`} className="inline-flex min-h-12 items-center justify-center rounded-full bg-[var(--accent)] px-6 font-semibold text-white hover:bg-[var(--accent-strong)]">Return to lobby</Link>
      </div>
    );
  }

  const turn = snapshot.currentTurn;
  const currentPlayer = snapshot.players.find((player) => player.id === turn.playerId);
  const currentDraw = snapshot.history.find(
    (draw) => draw.turnId === turn.id && draw.outcome === "current",
  );
  const isCurrentPlayer = currentPlayer?.userId === currentUserId;
  const isHost = snapshot.room.hostUserId === currentUserId;
  const history = [...snapshot.history].reverse();

  return (
    <div className="space-y-7">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Link href={`/room/${encodeURIComponent(code)}/lobby`} className="inline-flex min-h-11 items-center text-sm font-semibold text-[var(--accent)] hover:text-[var(--accent-strong)]">View lobby</Link>
        <div className="flex items-center gap-3 text-sm text-[var(--muted)]">
          <span className="font-semibold tracking-[0.14em] text-[var(--accent-strong)]">{snapshot.room.code}</span>
          <span className="inline-flex items-center gap-2">
            <span aria-hidden="true" className={`size-2 rounded-full ${connectionState === "connected" ? "bg-[#3f7a5f]" : "bg-[#b47c54]"}`} />
            {connectionLabels[connectionState]}
          </span>
        </div>
      </div>

      {errorMessage ? (
        <p role="alert" className="rounded-xl border border-[#e2b9aa] bg-[#fff3ee] px-4 py-3 text-sm leading-6 text-[#7b3521]">
          {errorMessage} The last confirmed game state is still shown.
        </p>
      ) : null}

      <section aria-labelledby="queue-heading">
        <div className="flex items-center justify-between gap-3">
          <h2 id="queue-heading" className="text-sm font-semibold uppercase tracking-[0.18em] text-[var(--warm)]">Player queue</h2>
          <button type="button" onClick={() => void refresh()} disabled={isRefreshing} className="min-h-11 rounded-full px-4 text-sm font-semibold text-[var(--accent)] hover:bg-[#edf4f0] disabled:cursor-wait disabled:text-[var(--muted)]">{isRefreshing ? "Refreshing..." : "Refresh"}</button>
        </div>
        <ol className="mt-3 flex items-start gap-3 overflow-x-auto pb-2">
          {snapshot.players.map((player) => {
            const isCurrent = player.id === turn.playerId;
            return (
              <li key={player.id} className={`min-w-40 rounded-xl border px-4 py-3 ${isCurrent ? "border-[var(--accent)] bg-[#edf4f0]" : "border-[var(--line)] bg-white"}`}>
                <p className="truncate font-semibold text-[var(--accent-strong)]">{player.displayName}{player.userId === currentUserId ? " (you)" : ""}</p>
                <p className="mt-1 text-xs text-[var(--muted)]">{isCurrent ? "Current player" : `Level ${player.selectedLevel}`}{player.isHost ? " · Host" : ""}</p>
                {isHost && player.userId !== currentUserId ? (
                  <PlayerManagementMenu
                    inline
                    player={player}
                    snapshot={snapshot}
                    replaceSnapshot={replaceSnapshot}
                  />
                ) : null}
              </li>
            );
          })}
        </ol>
      </section>

      <section aria-labelledby="prompt-heading" className="rounded-[1.75rem] border border-[#d8cbbb] bg-[#fffaf2] px-6 py-9 text-center shadow-[0_16px_45px_rgba(64,53,42,0.08)] sm:px-10 sm:py-12">
        <p className="text-sm font-semibold text-[var(--warm)]">
          {currentPlayer?.displayName ?? "Current player"} · Turn {turn.turnNumber}
        </p>
        {currentDraw ? (
          <>
            <div className="mt-4 flex flex-wrap justify-center gap-2 text-xs font-semibold uppercase tracking-[0.12em] text-[var(--muted)]">
              <span>Level {currentDraw.promptLevel}</span>
              <span aria-hidden="true">·</span>
              <span className="capitalize">{currentDraw.promptCategory}</span>
              <span aria-hidden="true">·</span>
              <span>{turn.redrawCount} {turn.redrawCount === 1 ? "redraw" : "redraws"}</span>
            </div>
            <h2 id="prompt-heading" className="mt-7 text-2xl font-semibold leading-10 tracking-[-0.02em] text-[var(--accent-strong)] sm:text-3xl sm:leading-12">{currentDraw.promptText}</h2>
          </>
        ) : (
          <>
            <h2 id="prompt-heading" className="mt-5 text-2xl font-semibold text-[var(--accent-strong)]">Ready for a card</h2>
            <p className="mt-3 text-[var(--muted)]">Waiting for {currentPlayer?.displayName ?? "the current player"} to choose a level and draw.</p>
          </>
        )}
      </section>

      {isCurrentPlayer ? (
        <TurnControls key={turn.id} snapshot={snapshot} replaceSnapshot={replaceSnapshot} />
      ) : (
        <p className="rounded-xl border border-[var(--line)] bg-white px-4 py-4 text-center text-sm text-[var(--muted)]">Listening while {currentPlayer?.displayName ?? "the current player"} takes their turn.</p>
      )}

      <details className="rounded-2xl border border-[var(--line)] bg-white p-5">
        <summary className="min-h-11 cursor-pointer font-semibold text-[var(--accent-strong)]">Prompt history ({snapshot.history.length})</summary>
        {history.length ? (
          <ol className="mt-4 space-y-3">
            {history.map((draw) => (
              <li key={draw.id} className="rounded-xl bg-[#f7f4ed] px-4 py-3">
                <div className="flex flex-wrap items-center justify-between gap-2 text-xs font-semibold text-[var(--muted)]">
                  <span>{draw.playerName} · Level {draw.promptLevel}</span>
                  <span>{outcomeLabels[draw.outcome]}</span>
                </div>
                <p className="mt-2 text-sm leading-6 text-[var(--foreground)]">{draw.promptText}</p>
              </li>
            ))}
          </ol>
        ) : (
          <p className="mt-3 text-sm text-[var(--muted)]">Drawn cards will appear here.</p>
        )}
      </details>

      <RoomLifecycleActions isHost={isHost} roomId={snapshot.room.id} />
    </div>
  );
}
