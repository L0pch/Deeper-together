"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { getGameErrorMessage } from "@/lib/game/errors";
import { fetchRoomSnapshotByCode } from "@/lib/game/room-service";
import { normaliseRoomCode } from "@/lib/game/validation";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type { RoomSnapshot } from "@/types/game";

export type RealtimeConnectionState = "connecting" | "connected" | "reconnecting" | "disconnected";

export function useRoomSnapshot(roomCode: string) {
  const code = normaliseRoomCode(roomCode);
  const [snapshot, setSnapshot] = useState<RoomSnapshot | null>(null);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [connectionState, setConnectionState] = useState<RealtimeConnectionState>("connecting");
  const latestRequest = useRef(0);
  const knownRoomId = useRef<string | undefined>(undefined);

  const handleReconcileError = useCallback((error: unknown) => {
    const rawMessage = error instanceof Error ? error.message : "";
    if (rawMessage.includes("room_access_denied") || rawMessage.includes("player_was_kicked")) {
      setSnapshot(null);
    }
    setErrorMessage(getGameErrorMessage(error));
  }, []);

  const replaceSnapshot = useCallback((nextSnapshot: RoomSnapshot) => {
    setSnapshot((currentSnapshot) => {
      if (currentSnapshot && nextSnapshot.room.stateVersion < currentSnapshot.room.stateVersion) {
        return currentSnapshot;
      }
      return nextSnapshot;
    });
  }, []);

  const reconcile = useCallback(async () => {
    const requestId = ++latestRequest.current;
    const result = await fetchRoomSnapshotByCode(code, knownRoomId.current);

    if (requestId !== latestRequest.current) return;
    knownRoomId.current = result.snapshot.room.id;
    setCurrentUserId(result.userId);
    replaceSnapshot(result.snapshot);
    setErrorMessage(null);
  }, [code, replaceSnapshot]);

  const refresh = useCallback(async () => {
    setIsRefreshing(true);
    try {
      await reconcile();
    } catch (error) {
      handleReconcileError(error);
    } finally {
      setIsRefreshing(false);
    }
  }, [handleReconcileError, reconcile]);

  useEffect(() => {
    let cancelled = false;
    const requestId = ++latestRequest.current;

    fetchRoomSnapshotByCode(code, knownRoomId.current)
      .then((result) => {
        if (cancelled || requestId !== latestRequest.current) return;
        knownRoomId.current = result.snapshot.room.id;
        setCurrentUserId(result.userId);
        replaceSnapshot(result.snapshot);
      })
      .catch((error: unknown) => {
        if (!cancelled) handleReconcileError(error);
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [code, handleReconcileError, replaceSnapshot]);

  const roomId = snapshot?.room.id;

  useEffect(() => {
    if (!roomId) return;

    const supabase = getSupabaseBrowserClient();
    let reconcileTimer: number | undefined;
    let subscriptionSettleTimer: number | undefined;

    const scheduleReconcile = (delayMs = 40) => {
      if (reconcileTimer) window.clearTimeout(reconcileTimer);
      reconcileTimer = window.setTimeout(() => {
        void reconcile().catch((error: unknown) => {
          handleReconcileError(error);
        });
      }, delayMs);
    };

    const reconcileWhenAvailable = () => {
      if (document.visibilityState === "visible" && navigator.onLine) {
        scheduleReconcile(0);
      }
    };

    window.addEventListener("focus", reconcileWhenAvailable);
    window.addEventListener("online", reconcileWhenAvailable);
    document.addEventListener("visibilitychange", reconcileWhenAvailable);

    const safetyReconcileInterval = window.setInterval(reconcileWhenAvailable, 30_000);

    const channel = supabase
      .channel(`room:${roomId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "rooms", filter: `id=eq.${roomId}` }, () => scheduleReconcile())
      .on("postgres_changes", { event: "*", schema: "public", table: "room_players", filter: `room_id=eq.${roomId}` }, () => scheduleReconcile())
      .on("postgres_changes", { event: "*", schema: "public", table: "turns", filter: `room_id=eq.${roomId}` }, () => scheduleReconcile())
      .on("postgres_changes", { event: "*", schema: "public", table: "prompt_draws", filter: `room_id=eq.${roomId}` }, () => scheduleReconcile())
      .subscribe((status) => {
        if (status === "SUBSCRIBED") {
          setConnectionState("connected");
          scheduleReconcile();
          if (subscriptionSettleTimer) window.clearTimeout(subscriptionSettleTimer);
          subscriptionSettleTimer = window.setTimeout(() => scheduleReconcile(), 1_000);
        } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
          setConnectionState("reconnecting");
        } else if (status === "CLOSED") {
          setConnectionState("disconnected");
        }
      });

    return () => {
      if (reconcileTimer) window.clearTimeout(reconcileTimer);
      if (subscriptionSettleTimer) window.clearTimeout(subscriptionSettleTimer);
      window.clearInterval(safetyReconcileInterval);
      window.removeEventListener("focus", reconcileWhenAvailable);
      window.removeEventListener("online", reconcileWhenAvailable);
      document.removeEventListener("visibilitychange", reconcileWhenAvailable);
      void supabase.removeChannel(channel);
    };
  }, [handleReconcileError, reconcile, roomId]);

  return {
    connectionState,
    currentUserId,
    errorMessage,
    isLoading,
    isRefreshing,
    refresh,
    replaceSnapshot,
    snapshot,
  };
}
