import { parseRoomSnapshot } from "@/lib/game/snapshot";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type { PromptLevel, RoomSnapshot } from "@/types/game";

export type RoomSnapshotResult = {
  snapshot: RoomSnapshot;
  userId: string;
};

export type RoomExitResult = {
  roomId: string;
  left?: boolean;
  closed?: boolean;
  roomClosed?: boolean;
};

export async function fetchRoomSnapshotByCode(
  code: string,
  knownRoomId?: string,
): Promise<RoomSnapshotResult> {
  const supabase = getSupabaseBrowserClient();
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();

  if (sessionError) throw sessionError;
  if (!sessionData.session?.user) throw new Error("room_access_denied");

  const { data: room, error: roomError } = await supabase
    .from("rooms")
    .select("id")
    .eq("code", code)
    .maybeSingle();

  if (roomError) throw roomError;
  if (!room) {
    if (knownRoomId) {
      const { data: membership, error: membershipError } = await supabase
        .from("room_players")
        .select("kicked_at,left_at")
        .eq("room_id", knownRoomId)
        .eq("user_id", sessionData.session.user.id)
        .maybeSingle();

      if (membershipError) throw membershipError;
      if (membership?.kicked_at) throw new Error("player_was_kicked");
    }
    throw new Error("room_access_denied");
  }

  const { data, error } = await supabase.rpc("get_room_snapshot", {
    p_room_id: room.id,
  });

  if (error) throw error;

  return {
    snapshot: parseRoomSnapshot(data),
    userId: sessionData.session.user.id,
  };
}

export async function setRoomLocked(roomId: string, isLocked: boolean): Promise<RoomSnapshot> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("set_room_locked", {
    p_room_id: roomId,
    p_is_locked: isLocked,
  });

  if (error) throw error;
  return parseRoomSnapshot(data);
}

export async function startRoomGame(roomId: string): Promise<RoomSnapshot> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("start_game", {
    p_room_id: roomId,
  });

  if (error) throw error;
  return parseRoomSnapshot(data);
}

export async function drawRoomPrompt(
  roomId: string,
  turnId: string,
  level: PromptLevel,
): Promise<RoomSnapshot> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("draw_prompt", {
    p_room_id: roomId,
    p_turn_id: turnId,
    p_level: level,
  });

  if (error) throw error;
  return parseRoomSnapshot(data);
}

export async function completeRoomTurn(
  roomId: string,
  turnId: string,
  skipped: boolean,
): Promise<RoomSnapshot> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("complete_turn", {
    p_room_id: roomId,
    p_turn_id: turnId,
    p_skipped: skipped,
  });

  if (error) throw error;
  return parseRoomSnapshot(data);
}

export async function leaveRoom(roomId: string): Promise<RoomExitResult> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("leave_room", { p_room_id: roomId });

  if (error) throw error;
  return data as RoomExitResult;
}

export async function kickRoomPlayer(roomId: string, playerId: string): Promise<RoomSnapshot> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("kick_player", {
    p_room_id: roomId,
    p_player_id: playerId,
  });

  if (error) throw error;
  return parseRoomSnapshot(data);
}

export async function makeRoomHost(roomId: string, playerId: string): Promise<RoomSnapshot> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("make_host", {
    p_room_id: roomId,
    p_player_id: playerId,
  });

  if (error) throw error;
  return parseRoomSnapshot(data);
}

export async function playRoomPlayerNow(
  roomId: string,
  playerId: string,
  turnId: string,
): Promise<RoomSnapshot> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("play_now", {
    p_room_id: roomId,
    p_player_id: playerId,
    p_turn_id: turnId,
  });

  if (error) throw error;
  return parseRoomSnapshot(data);
}

export async function closeRoom(roomId: string): Promise<RoomExitResult> {
  const supabase = getSupabaseBrowserClient();
  const { data, error } = await supabase.rpc("close_room", { p_room_id: roomId });

  if (error) throw error;
  return data as RoomExitResult;
}
