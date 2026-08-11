import type { Json } from "@/types/json";

export type Database = {
  public: {
    Tables: {
      rooms: {
        Row: { id: string; code: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      room_players: {
        Row: {
          id: string;
          room_id: string;
          user_id: string;
          left_at: string | null;
          kicked_at: string | null;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      turns: {
        Row: { id: string; room_id: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      prompt_draws: {
        Row: { id: string; room_id: string };
        Insert: never;
        Update: never;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: {
      create_room: {
        Args: { p_display_name: string; p_selected_level?: number };
        Returns: Json;
      };
      draw_prompt: {
        Args: { p_room_id: string; p_turn_id: string; p_level: number };
        Returns: Json;
      };
      complete_turn: {
        Args: { p_room_id: string; p_turn_id: string; p_skipped?: boolean };
        Returns: Json;
      };
      join_room: {
        Args: {
          p_room_code: string;
          p_display_name: string;
          p_selected_level?: number;
        };
        Returns: Json;
      };
      leave_room: {
        Args: { p_room_id: string };
        Returns: Json;
      };
      kick_player: {
        Args: { p_room_id: string; p_player_id: string };
        Returns: Json;
      };
      make_host: {
        Args: { p_room_id: string; p_player_id: string };
        Returns: Json;
      };
      play_now: {
        Args: { p_room_id: string; p_player_id: string; p_turn_id: string };
        Returns: Json;
      };
      close_room: {
        Args: { p_room_id: string };
        Returns: Json;
      };
      get_admin_prompt_catalog: {
        Args: {
          p_search: string | null;
          p_level: number | null;
          p_category_id: string | null;
          p_status: string;
          p_limit: number;
          p_offset: number;
        };
        Returns: Json;
      };
      save_admin_prompt: {
        Args: {
          p_prompt_text: string;
          p_level: number;
          p_category_id: string;
          p_prompt_id: string | null;
        };
        Returns: Json;
      };
      set_admin_prompt_state: {
        Args: { p_prompt_id: string; p_action: string };
        Returns: Json;
      };
      import_admin_prompts: {
        Args: { p_rows: Json };
        Returns: Json;
      };
      get_admin_prompt_export: {
        Args: Record<PropertyKey, never>;
        Returns: Json;
      };
      sync_google_sheet_prompts: {
        Args: { p_rows: Json };
        Returns: Json;
      };
      get_room_snapshot: {
        Args: { p_room_id: string };
        Returns: Json;
      };
      set_room_locked: {
        Args: { p_room_id: string; p_is_locked: boolean };
        Returns: Json;
      };
      start_game: {
        Args: { p_room_id: string };
        Returns: Json;
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
