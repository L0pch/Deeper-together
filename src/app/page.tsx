import Link from "next/link";

import { SiteHeader } from "@/components/site-header";

const principles = [
  { number: "01", title: "Gather your people", body: "Create a private room and share its simple code with your group." },
  { number: "02", title: "Choose your depth", body: "Pick from light, reflective, or deeper questions each time you play." },
  { number: "03", title: "Share at your pace", body: "Every question can be redrawn. No explanation is ever required." },
];

export default function Home() {
  return (
    <div className="min-h-screen">
      <SiteHeader />
      <main>
        <section className="mx-auto grid min-h-[calc(100vh-5rem)] max-w-6xl items-center gap-14 px-5 py-16 sm:px-8 lg:grid-cols-[1.08fr_0.92fr] lg:px-10 lg:py-24">
          <div>
            <p className="mb-5 text-sm font-semibold uppercase tracking-[0.22em] text-[var(--warm)]">Conversation worth making room for</p>
            <h1 className="max-w-3xl text-5xl font-semibold leading-[1.02] tracking-[-0.045em] text-[var(--accent-strong)] sm:text-6xl lg:text-7xl">
              Less small talk.<br />More <span className="text-[var(--warm)]">together.</span>
            </h1>
            <p className="mt-7 max-w-xl text-lg leading-8 text-[var(--muted)] sm:text-xl">
              A welcoming conversation card game for Christian friends, cell groups, and communities who want to know one another more deeply.
            </p>
            <div className="mt-9 flex flex-col gap-3 sm:flex-row">
              <Link href="/create" className="inline-flex min-h-12 items-center justify-center rounded-full bg-[var(--accent)] px-7 py-3 font-semibold text-white transition hover:bg-[var(--accent-strong)]">Create a room</Link>
              <Link href="/join" className="inline-flex min-h-12 items-center justify-center rounded-full border border-[var(--line)] bg-[var(--surface)] px-7 py-3 font-semibold text-[var(--accent-strong)] transition hover:border-[#b7c5bd] hover:bg-white">Join with a code</Link>
            </div>
          </div>
          <div className="relative mx-auto w-full max-w-md">
            <div className="absolute -left-5 top-9 h-full w-full rotate-[-4deg] rounded-[2rem] border border-[#ddc9b8] bg-[#efdac8]" />
            <article className="relative flex min-h-[29rem] flex-col justify-between rounded-[2rem] border border-[var(--line)] bg-[var(--surface)] p-8 shadow-[0_24px_70px_rgba(50,65,57,0.12)] sm:p-10">
              <div className="flex items-center justify-between text-sm font-semibold">
                <span className="rounded-full bg-[#e3eee8] px-3 py-1.5 text-[var(--accent)]">Level 2 · Reflect</span>
                <span className="text-[var(--muted)]">Your turn</span>
              </div>
              <blockquote className="text-3xl font-medium leading-[1.25] tracking-[-0.025em] text-[var(--accent-strong)] sm:text-4xl">What has God been teaching you in this season?</blockquote>
              <p className="border-t border-[var(--line)] pt-5 text-sm leading-6 text-[var(--muted)]">You can always redraw a card. The best conversations are freely chosen.</p>
            </article>
          </div>
        </section>
        <section className="border-y border-[var(--line)] bg-[var(--surface)]">
          <div className="mx-auto grid max-w-6xl gap-0 px-5 py-4 sm:px-8 md:grid-cols-3 lg:px-10">
            {principles.map((principle) => (
              <article key={principle.number} className="border-b border-[var(--line)] py-8 last:border-0 md:border-b-0 md:border-r md:px-8 md:first:pl-0 md:last:border-r-0 md:last:pr-0">
                <p className="text-sm font-semibold text-[var(--warm)]">{principle.number}</p>
                <h2 className="mt-3 text-xl font-semibold text-[var(--accent-strong)]">{principle.title}</h2>
                <p className="mt-2 leading-7 text-[var(--muted)]">{principle.body}</p>
              </article>
            ))}
          </div>
        </section>
      </main>
    </div>
  );
}
