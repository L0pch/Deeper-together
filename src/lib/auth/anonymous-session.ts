import type { SupabaseClient, User } from "@supabase/supabase-js";

import type { Database } from "@/lib/supabase/database.types";

export async function ensureAnonymousUser(
  supabase: SupabaseClient<Database>,
): Promise<User> {
  const { data: sessionData, error: sessionError } =
    await supabase.auth.getSession();

  if (sessionError) throw sessionError;
  if (sessionData.session?.user) return sessionData.session.user;

  const { data, error } = await supabase.auth.signInAnonymously();

  if (error) throw error;
  if (!data.user) throw new Error("anonymous_authentication_failed");

  return data.user;
}
