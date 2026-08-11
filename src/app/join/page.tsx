import type { Metadata } from "next";

import { RoomEntryForm } from "@/components/room-entry-form";
import { RouteShell } from "@/components/route-shell";

export const metadata: Metadata = { title: "Join a room" };

type JoinRoomPageProps = { searchParams: Promise<{ code?: string | string[] }> };

export default async function JoinRoomPage({ searchParams }: JoinRoomPageProps) {
  const requestedCode = (await searchParams).code;
  const defaultRoomCode = Array.isArray(requestedCode) ? requestedCode[0] : requestedCode;

  return (
    <RouteShell eyebrow="Come on in" title="Join a room" description="Enter the room code shared by your host. You can join after a game starts unless the room is locked.">
      <RoomEntryForm mode="join" defaultRoomCode={defaultRoomCode} />
    </RouteShell>
  );
}
