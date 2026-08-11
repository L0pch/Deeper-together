import type {
  AdminPromptCategory,
  AdminPromptTag,
  AdminPromptTransferRow,
  AdminPromptTransferStatus,
} from "@/types/admin";
import type { PromptLevel } from "@/types/game";

const headers = ["prompt_text", "level", "category", "tags", "status"] as const;

function parseCsvTable(source: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (quoted) {
      if (character === '"') {
        if (source[index + 1] === '"') {
          field += '"';
          index += 1;
        } else {
          quoted = false;
        }
      } else {
        field += character;
      }
      continue;
    }

    if (character === '"' && field.length === 0) {
      quoted = true;
    } else if (character === ",") {
      row.push(field);
      field = "";
    } else if (character === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (character !== "\r") {
      field += character;
    }
  }

  if (quoted) throw new Error("The CSV contains an unclosed quoted value.");
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows.filter((candidate) => candidate.some((value) => value.trim() !== ""));
}

function escapeCsvField(value: string): string {
  return /[",\r\n]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value;
}

export function normaliseTagSlug(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export function parseAdminPromptCsv(
  source: string,
  categories: AdminPromptCategory[],
  tags: AdminPromptTag[],
): AdminPromptTransferRow[] {
  const table = parseCsvTable(source.replace(/^\uFEFF/, ""));
  if (table.length < 2) throw new Error("The CSV must contain a header and at least one prompt row.");

  const headerIndexes = new Map(table[0].map((header, index) => [header.trim().toLowerCase(), index]));
  for (const header of headers) {
    if (!headerIndexes.has(header)) throw new Error(`The CSV is missing the '${header}' column.`);
  }

  if (table.length - 1 > 500) throw new Error("Import no more than 500 prompt rows at a time.");

  const activeCategories = new Set(categories.filter((category) => category.isActive).map((category) => category.id));
  const activeTags = new Set(tags.filter((tag) => tag.isActive).map((tag) => tag.slug));

  return table.slice(1).map((row, rowIndex) => {
    const line = rowIndex + 2;
    const read = (header: typeof headers[number]) => row[headerIndexes.get(header) ?? -1]?.trim() ?? "";
    const promptText = read("prompt_text");
    const levelValue = read("level");
    const categoryId = read("category").toLowerCase();
    const statusValue = read("status").toLowerCase();
    const tagSlugs = [...new Set(read("tags").split("|").map((tag) => tag.trim().toLowerCase()).filter(Boolean))];

    if (!promptText || promptText.length > 500 || /[\u0000-\u001f\u007f]/.test(promptText)) {
      throw new Error(`Row ${line}: prompt_text must contain 1 to 500 plain-text characters.`);
    }
    if (levelValue !== "1" && levelValue !== "2" && levelValue !== "3") {
      throw new Error(`Row ${line}: level must be 1, 2, or 3.`);
    }
    if (!activeCategories.has(categoryId)) {
      throw new Error(`Row ${line}: category '${categoryId || "(blank)"}' is not available.`);
    }
    if (statusValue !== "active" && statusValue !== "inactive" && statusValue !== "archived") {
      throw new Error(`Row ${line}: status must be active, inactive, or archived.`);
    }
    const unavailableTag = tagSlugs.find((slug) => !activeTags.has(slug));
    if (unavailableTag) throw new Error(`Row ${line}: tag '${unavailableTag}' is missing or inactive.`);

    return {
      promptText,
      level: Number(levelValue) as PromptLevel,
      categoryId,
      tags: tagSlugs,
      status: statusValue as AdminPromptTransferStatus,
    };
  });
}

export function serializeAdminPromptCsv(rows: AdminPromptTransferRow[]): string {
  const serializedRows = rows.map((row) => [
    row.promptText,
    String(row.level),
    row.categoryId,
    row.tags.join("|"),
    row.status,
  ].map(escapeCsvField).join(","));

  return `${headers.join(",")}\r\n${serializedRows.join("\r\n")}\r\n`;
}

export function createAdminPromptCsvTemplate(
  categories: AdminPromptCategory[],
  tags: AdminPromptTag[],
): string {
  const categoryId = categories.find((category) => category.isActive)?.id ?? "secular";
  const tagSlugs = tags.filter((tag) => tag.isActive).slice(0, 2).map((tag) => tag.slug);
  return serializeAdminPromptCsv([{
    promptText: "Replace this example with your prompt text",
    level: 1,
    categoryId,
    tags: tagSlugs,
    status: "active",
  }]);
}
