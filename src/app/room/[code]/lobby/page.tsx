import type { Metadata } from "next";

import { LobbyClient } from "@/components/lobby-client";
import { RouteShell } from "@/components/route-shell";

export const metadata: Metadata = { title: "Room lobby" };

export default async function LobbyPage(props: PageProps<"/room/[code]/lobby">) {
  const { code } = await props.params;

  return (
    <RouteShell eyebrow={`Room ${code.toUpperCase()}`} title="Gathering in the lobby" description="Share the code, check the queue, and get ready for meaningful conversation.">
      <LobbyClient roomCode={code} />
    </RouteShell>
  );
}
