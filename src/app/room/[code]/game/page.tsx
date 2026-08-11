import type { Metadata } from "next";

import { GameClient } from "@/components/game-client";
import { RouteShell } from "@/components/route-shell";

export const metadata: Metadata = { title: "Game room" };

export default async function GameRoomPage(props: PageProps<"/room/[code]/game">) {
  const { code } = await props.params;

  return (
    <RouteShell eyebrow={`Room ${code.toUpperCase()}`} title="The conversation starts here" description="Take turns drawing, listening, and sharing at a level that feels right for you.">
      <GameClient roomCode={code} />
    </RouteShell>
  );
}
