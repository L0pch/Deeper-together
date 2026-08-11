"use client";

import { useState } from "react";

import { PromptLevelPicker } from "@/components/prompt-level-picker";
import { getGameErrorMessage } from "@/lib/game/errors";
import { completeRoomTurn, drawRoomPrompt } from "@/lib/game/room-service";
import type { PromptLevel, RoomSnapshot } from "@/types/game";

type TurnControlsProps = {
  snapshot: RoomSnapshot;
  replaceSnapshot: (snapshot: RoomSnapshot) => void;
};

export function TurnControls({ snapshot, replaceSnapshot }: TurnControlsProps) {
  const turn = snapshot.currentTurn;
  const [selectedLevel, setSelectedLevel] = useState<PromptLevel>(turn?.selectedLevel ?? 1);
  const [activeAction, setActiveAction] = useState<"draw" | "done" | "skip" | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  if (!turn) return null;
  const turnId = turn.id;

  const currentDraw = snapshot.history.find(
    (draw) => draw.turnId === turnId && draw.outcome === "current",
  );

  async function handleDraw() {
    setActiveAction("draw");
    setErrorMessage(null);
    try {
      replaceSnapshot(await drawRoomPrompt(snapshot.room.id, turnId, selectedLevel));
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setActiveAction(null);
    }
  }

  async function handleComplete(skipped: boolean) {
    setActiveAction(skipped ? "skip" : "done");
    setErrorMessage(null);
    try {
      replaceSnapshot(await completeRoomTurn(snapshot.room.id, turnId, skipped));
    } catch (error) {
      setErrorMessage(getGameErrorMessage(error));
    } finally {
      setActiveAction(null);
    }
  }

  return (
    <section aria-labelledby="turn-controls-heading" className="rounded-2xl border border-[#cfc5b6] bg-[#fffdf8] p-5 shadow-[0_14px_38px_rgba(37,55,47,0.14)]">
      <h2 id="turn-controls-heading" className="text-lg font-semibold text-[var(--accent-strong)]">Your turn</h2>

      <div className="mt-4">
        <PromptLevelPicker
          value={selectedLevel}
          onChange={setSelectedLevel}
          disabled={activeAction !== null}
          legend="Prompt level"
          description={currentDraw ? "Changing this applies to your next redraw. It will not change the visible card." : "Choose how deep you would like this turn's conversation to go."}
        />
      </div>

      <button type="button" onClick={() => void handleDraw()} disabled={activeAction !== null} className="mt-5 min-h-12 w-full rounded-full bg-[var(--accent)] px-6 font-semibold text-white hover:bg-[var(--accent-strong)] disabled:cursor-wait disabled:bg-[#8ca097]">
        {activeAction === "draw" ? "Drawing..." : currentDraw ? "Draw another card" : "Draw a card"}
      </button>

      {currentDraw ? (
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <button type="button" onClick={() => void handleComplete(false)} disabled={activeAction !== null} className="min-h-12 rounded-full border border-[var(--accent)] bg-white px-5 font-semibold text-[var(--accent-strong)] hover:bg-[#edf4f0] disabled:cursor-wait disabled:text-[var(--muted)]">
            {activeAction === "done" ? "Finishing..." : "Done sharing"}
          </button>
          <button type="button" onClick={() => void handleComplete(true)} disabled={activeAction !== null} className="min-h-12 rounded-full border border-[var(--line)] bg-white px-5 font-semibold text-[var(--muted)] hover:bg-[#f5f1e9] disabled:cursor-wait">
            {activeAction === "skip" ? "Skipping..." : "Skip turn"}
          </button>
        </div>
      ) : null}

      {errorMessage ? (
        <p role="alert" className="mt-4 rounded-xl border border-[#e2b9aa] bg-[#fff3ee] px-4 py-3 text-sm leading-6 text-[#7b3521]">{errorMessage}</p>
      ) : null}

      <p className="mt-4 text-center text-xs leading-5 text-[var(--muted)]">
        You can redraw or skip without giving a reason.
      </p>
    </section>
  );
}
