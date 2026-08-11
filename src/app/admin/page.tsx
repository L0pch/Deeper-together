import type { Metadata } from "next";

import { AdminClient } from "@/components/admin-client";
import { RouteShell } from "@/components/route-shell";

export const metadata: Metadata = { title: "Prompt administration" };

export default function AdminPage() {
  return (
    <RouteShell
      eyebrow="Protected administration"
      title="Prompt library"
      description="Create, refine, organize, and retire conversation cards without changing previously drawn room history."
    >
      <AdminClient />
    </RouteShell>
  );
}
