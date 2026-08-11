import type { PromptLevel } from "@/types/game";

export const DISPLAY_NAME_MAX_LENGTH = 40;

const controlCharacterPattern = /[\u0000-\u001f\u007f]/;
const roomCodePattern = /^[A-HJ-NP-Z2-9]{6}$/;

export function normaliseDisplayName(value: string): string {
  return value.trim();
}

export function getDisplayNameError(value: string): string | null {
  const displayName = normaliseDisplayName(value);

  if (!displayName) return "Enter the name you would like the group to see.";
  if (displayName.length > DISPLAY_NAME_MAX_LENGTH) {
    return `Keep your display name to ${DISPLAY_NAME_MAX_LENGTH} characters or fewer.`;
  }
  if (controlCharacterPattern.test(displayName)) {
    return "That display name contains unsupported characters.";
  }

  return null;
}

export function normaliseRoomCode(value: string): string {
  return value.trim().toUpperCase();
}

export function getRoomCodeError(value: string): string | null {
  const roomCode = normaliseRoomCode(value);

  if (!roomCode) return "Enter the six-character room code shared by your host.";
  if (!roomCodePattern.test(roomCode)) {
    return "Check the room code. It should contain six uppercase letters or numbers.";
  }

  return null;
}

export function isPromptLevel(value: number): value is PromptLevel {
  return value === 1 || value === 2 || value === 3;
}
