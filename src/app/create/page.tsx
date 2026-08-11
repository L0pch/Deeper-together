import type { Metadata } from "next";

import { RoomEntryForm } from "@/components/room-entry-form";
import { RouteShell } from "@/components/route-shell";

export const metadata: Metadata = { title: "Create a room" };

export default function CreateRoomPage() {
  return (
    <RouteShell eyebrow="Start a gathering" title="Create a room" description="You'll become the host and can invite up to 19 more people.">
      <RoomEntryForm mode="create" />
    </RouteShell>
  );
}
