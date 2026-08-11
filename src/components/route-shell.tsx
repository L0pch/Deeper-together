import Link from "next/link";
import type { ReactNode } from "react";

import { SiteHeader } from "@/components/site-header";

type RouteShellProps = { eyebrow: string; title: string; description: string; children: ReactNode };

export function RouteShell({ eyebrow, title, description, children }: RouteShellProps) {
  return (
    <div className="min-h-screen">
      <SiteHeader />
      <main className="mx-auto w-full max-w-3xl px-5 py-12 sm:px-8 sm:py-16">
        <Link href="/" className="inline-flex min-h-11 items-center text-sm font-semibold text-[var(--accent)] hover:text-[var(--accent-strong)]">← Back home</Link>
        <section className="mt-8">
          <p className="text-sm font-semibold uppercase tracking-[0.2em] text-[var(--warm)]">{eyebrow}</p>
          <h1 className="mt-3 text-4xl font-semibold tracking-[-0.035em] text-[var(--accent-strong)] sm:text-5xl">{title}</h1>
          <p className="mt-4 max-w-2xl text-lg leading-8 text-[var(--muted)]">{description}</p>
          <div className="mt-9 rounded-[1.5rem] border border-[var(--line)] bg-[var(--surface)] p-6 shadow-[0_16px_50px_rgba(50,65,57,0.08)] sm:p-8">{children}</div>
        </section>
      </main>
    </div>
  );
}
