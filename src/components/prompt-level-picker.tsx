import type { PromptLevel } from "@/types/game";

const levels: Array<{ value: PromptLevel; label: string; description: string }> = [
  { value: 1, label: "Level 1", description: "Light and easy" },
  { value: 2, label: "Level 2", description: "Reflective and personal" },
  { value: 3, label: "Level 3", description: "Deep and vulnerable" },
];

type PromptLevelPickerProps = {
  value: PromptLevel;
  onChange: (level: PromptLevel) => void;
  disabled?: boolean;
  legend?: string;
  description?: string;
};

export function PromptLevelPicker({
  value,
  onChange,
  disabled = false,
  legend = "Starting prompt level",
  description = "This is your preference for future turns. You can change it later.",
}: PromptLevelPickerProps) {
  return (
    <fieldset disabled={disabled}>
      <legend className="text-sm font-semibold text-[var(--accent-strong)]">{legend}</legend>
      <p className="mt-1 text-sm leading-6 text-[var(--muted)]">
        {description}
      </p>
      <div className="mt-3 grid gap-3 sm:grid-cols-3">
        {levels.map((level) => {
          const selected = level.value === value;
          return (
            <label key={level.value} className={`cursor-pointer rounded-xl border p-4 transition-colors ${selected ? "border-[var(--accent)] bg-[#edf4f0]" : "border-[var(--line)] bg-white hover:border-[#9aaca3]"}`}>
              <input type="radio" name="prompt-level" value={level.value} checked={selected} onChange={() => onChange(level.value)} className="sr-only" />
              <span className="block font-semibold text-[var(--accent-strong)]">{level.label}</span>
              <span className="mt-1 block text-sm leading-5 text-[var(--muted)]">{level.description}</span>
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}
