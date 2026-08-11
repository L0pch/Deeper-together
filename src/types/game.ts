export type PromptLevel = 1 | 2 | 3;

export type RoomStatus = "lobby" | "active" | "ended" | "closed";

export type TurnStatus =
  | "awaiting_draw"
  | "sharing"
  | "completed"
  | "skipped"
  | "cancelled";

export type DrawOutcome = "current" | "redrawn" | "answered" | "skipped";

export type RoomSnapshot = {
  room: {
    id: string;
    code: string;
    status: RoomStatus;
    hostUserId: string;
    isLocked: boolean;
    maxPlayers: number;
    currentTurnId: string | null;
    stateVersion: number;
    expiresAt: string;
  };
  players: RoomPlayerSnapshot[];
  currentTurn: TurnSnapshot | null;
  history: PromptDrawSnapshot[];
};

export type RoomPlayerSnapshot = {
  id: string;
  userId: string;
  displayName: string;
  avatarKey: string | null;
  avatarColour: string | null;
  selectedLevel: PromptLevel;
  queuePosition: number;
  isHost: boolean;
  joinedAt: string;
};

export type TurnSnapshot = {
  id: string;
  playerId: string;
  turnNumber: number;
  status: TurnStatus;
  selectedLevel: PromptLevel;
  redrawCount: number;
  startedAt: string;
};

export type PromptDrawSnapshot = {
  id: string;
  turnId: string;
  playerId: string;
  playerName: string;
  promptText: string;
  promptLevel: PromptLevel;
  promptCategory: string;
  promptTags: string[];
  drawNumber: number;
  outcome: DrawOutcome;
  drawnAt: string;
};
