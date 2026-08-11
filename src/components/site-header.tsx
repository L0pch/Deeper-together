import Link from "next/link";

export function SiteHeader() {
  return (
    <header className="border-b border-[var(--line)] bg-[color:rgba(247,244,237,0.88)]">
      <div className="mx-auto flex h-20 max-w-6xl items-center justify-between px-5 sm:px-8 lg:px-10">
        <Link href="/" aria-label="Deeper Together home" className="inline-flex items-center gap-3 font-semibold tracking-[-0.02em] text-[var(--accent-strong)]">
          <span aria-hidden="true" className="grid size-9 place-items-center rounded-full bg-[var(--accent)] text-sm text-white">DT</span>
          <span>Deeper Together</span>
        </Link>
        <span className="hidden text-sm text-[var(--muted)] sm:block">Listen · Share · Grow</span>
      </div>
    </header>
  );
}
