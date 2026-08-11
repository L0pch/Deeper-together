import type { RoomSnapshot } from "@/types/game";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parseRoomSnapshot(value: unknown): RoomSnapshot {
  if (!isRecord(value) || !isRecord(value.room) || !Array.isArray(value.players)) {
    throw new Error("invalid_room_snapshot");
  }

  const room = value.room;

  if (
    typeof room.id !== "string" ||
    typeof room.code !== "string" ||
    typeof room.hostUserId !== "string" ||
    typeof room.status !== "string" ||
    typeof room.isLocked !== "boolean" ||
    typeof room.maxPlayers !== "number" ||
    typeof room.stateVersion !== "number" ||
    typeof room.expiresAt !== "string" ||
    !value.players.every(
      (player) =>
        isRecord(player) &&
        typeof player.id === "string" &&
        typeof player.displayName === "string" &&
        typeof player.queuePosition === "number" &&
        typeof player.isHost === "boolean",
    )
  ) {
    throw new Error("invalid_room_snapshot");
  }

  return value as RoomSnapshot;
}
