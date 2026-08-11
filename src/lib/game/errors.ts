type ErrorLike = { message?: unknown };

const errorMessages: Record<string, string> = {
  admin_permission_required: "This signed-in account is not authorized to manage prompts.",
  admin_strong_authentication_required: "Sign in with an administrator email and password to continue.",
  anonymous_authentication_failed: "We could not start your private guest session. Please try again.",
  authentication_required: "Your guest session could not be verified. Please try again.",
  current_player_required: "Only the current player can do that.",
  host_permission_required: "Only the room host can do that.",
  invalid_display_name: "Please check your display name and try again.",
  invalid_host_action: "That host action was not valid. Refresh the room and try again.",
  invalid_turn_action: "That turn action was not valid. Refresh the game and try again.",
  invalid_prompt_level: "Please choose one of the three prompt levels.",
  invalid_prompt_text: "Prompt text must contain between 1 and 500 plain-text characters.",
  invalid_prompt_category: "Choose an available prompt category.",
  invalid_prompt_tags: "One or more selected prompt tags are no longer available.",
  invalid_prompt_state_action: "That prompt status change was not valid.",
  invalid_admin_response: "The prompt service returned an unexpected response. Please refresh and try again.",
  invalid_admin_search: "Keep prompt searches to 100 characters or fewer.",
  invalid_admin_pagination: "That prompt list request was not valid.",
  invalid_prompt_import_size: "Import between 1 and 500 prompts at a time.",
  invalid_prompt_import_category: "The import contains a category that is not available.",
  invalid_prompt_import_tags: "The import contains a tag that is missing or inactive.",
  invalid_prompt_import_row: "One or more imported prompt rows are invalid.",
  invalid_prompt_import: "That prompt import file could not be processed.",
  invalid_tag_name: "Tag names must contain between 1 and 40 plain-text characters.",
  invalid_tag_slug: "Use lowercase letters, numbers, and single hyphens for the tag slug.",
  invalid_tag_state: "That tag status change was not valid.",
  tag_slug_exists: "That tag slug is already in use.",
  tag_not_found: "That tag could not be found. Refresh and try again.",
  prompt_not_found: "That prompt could not be found. It may have changed since your last refresh.",
  invalid_room_state: "That action is not available in the room's current state.",
  invalid_room_action: "That room action was not valid. Refresh and try again.",
  no_prompts_available: "No active prompts are available at that level yet. Choose another level.",
  invalid_room_code: "Check the room code and try again.",
  player_was_kicked: "You were removed from this room by its host.",
  player_not_active: "That player is no longer active in the room.",
  cannot_kick_host: "Transfer host status before removing the current host.",
  room_access_denied: "This browser does not have access to that room.",
  room_code_generation_failed: "We could not create a room code just now. Please try again.",
  room_is_full: "That room has reached its player limit.",
  room_is_locked: "That room is currently locked by its host.",
  room_has_no_players: "At least one active player is needed to start the game.",
  room_not_active: "That game is not currently active.",
  prompt_required: "Draw a card before completing this turn.",
  rate_limit_exceeded: "You're doing that too quickly. Wait a moment and try again.",
  stale_turn: "The turn has already changed. The latest game state has been loaded.",
  room_not_found: "That room could not be found. Check the code and try again.",
  supabase_configuration_missing: "The game service is not configured. Please let the site owner know.",
};

export function getGameErrorMessage(error: unknown): string {
  const rawMessage =
    typeof error === "object" && error !== null
      ? (error as ErrorLike).message
      : undefined;
  const message = typeof rawMessage === "string" ? rawMessage : "";

  for (const [key, friendlyMessage] of Object.entries(errorMessages)) {
    if (message.includes(key)) return friendlyMessage;
  }

  return "Something went wrong while contacting the game service. Please try again.";
}
