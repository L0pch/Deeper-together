import type {
  AdminPromptCategory,
  AdminPromptTransferRow,
  AdminPromptTransferStatus,
} from "@/types/admin";
import type { PromptLevel } from "@/types/game";

const headers = ["prompt_text", "level", "category", "status"] as const;

function detectDelimiter(source: string): "," | "\t" {
  const firstLine = source.split(/\r?\n/, 1)[0] ?? "";
  return firstLine.includes("\t") ? "\t" : ",";
}

function parseDelimitedTable(source: string, delimiter: "," | "\t"): string[][] {
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
    } else if (character === delimiter) {
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

  if (quoted) throw new Error("The table contains an unclosed quoted value.");
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows.filter((candidate) => candidate.some((value) => value.trim() !== ""));
}

function parsePromptRows(
  table: string[][],
  activeCategoryIds?: ReadonlySet<string>,
): AdminPromptTransferRow[] {
  if (table.length < 2) {
    throw new Error("Include a header row and at least one prompt row.");
  }

  const headerIndexes = new Map(
    table[0].map((header, index) => [header.trim().toLowerCase(), index]),
  );
  for (const header of headers) {
    if (!headerIndexes.has(header)) {
      throw new Error("The table is missing the '" + header + "' column.");
    }
  }

  if (table.length - 1 > 500) {
    throw new Error("Import no more than 500 prompt rows at a time.");
  }

  let inheritedCategoryId = "";
  let inheritedStatus: AdminPromptTransferStatus = "active";

  return table.slice(1).map((row, rowIndex) => {
    const line = rowIndex + 2;
    const read = (header: (typeof headers)[number]) =>
      row[headerIndexes.get(header) ?? -1]?.trim() ?? "";
    const promptText = read("prompt_text");
    const levelValue = read("level");
    const categoryValue = read("category").toLowerCase();
    const statusValue = read("status").toLowerCase();

    if (categoryValue) inheritedCategoryId = categoryValue;
    if (statusValue === "active" || statusValue === "inactive" || statusValue === "archived") {
      inheritedStatus = statusValue;
    }

    const categoryId = categoryValue || inheritedCategoryId;
    const status = statusValue || inheritedStatus;

    if (!promptText || promptText.length > 500 || /[\u0000-\u001f\u007f]/.test(promptText)) {
      throw new Error("Row " + line + ": prompt_text must contain 1 to 500 plain-text characters.");
    }
    if (levelValue !== "1" && levelValue !== "2" && levelValue !== "3") {
      throw new Error("Row " + line + ": level must be 1, 2, or 3.");
    }
    if (!categoryId || (activeCategoryIds && !activeCategoryIds.has(categoryId))) {
      throw new Error(
        "Row " + line + ": category '" + (categoryId || "(blank)") + "' is not available.",
      );
    }
    if (status !== "active" && status !== "inactive" && status !== "archived") {
      throw new Error("Row " + line + ": status must be active, inactive, or archived.");
    }

    return {
      promptText,
      level: Number(levelValue) as PromptLevel,
      categoryId,
      status,
    };
  });
}

function escapeCsvField(value: string): string {
  return /[",\r\n]/.test(value) ? '"' + value.replaceAll('"', '""') + '"' : value;
}

export function parseAdminPromptTable(
  source: string,
  categories: AdminPromptCategory[],
): AdminPromptTransferRow[] {
  const normalizedSource = source.replace(/^\uFEFF/, "");
  const table = parseDelimitedTable(normalizedSource, detectDelimiter(normalizedSource));
  const activeCategoryIds = new Set(
    categories.filter((category) => category.isActive).map((category) => category.id),
  );
  return parsePromptRows(table, activeCategoryIds);
}

export function parseGoogleSheetPromptValues(values: unknown[][]): AdminPromptTransferRow[] {
  const table = values.map((row) => row.map((value) => String(value ?? "")));
  return parsePromptRows(table);
}

export const parseAdminPromptCsv = parseAdminPromptTable;

export function serializeAdminPromptCsv(rows: AdminPromptTransferRow[]): string {
  const serializedRows = rows.map((row) => [
    row.promptText,
    String(row.level),
    row.categoryId,
    row.status,
  ].map(escapeCsvField).join(","));

  return headers.join(",") + "\r\n" + serializedRows.join("\r\n") + "\r\n";
}

export function createAdminPromptCsvTemplate(
  categories: AdminPromptCategory[],
): string {
  const categoryId = categories.find((category) => category.isActive)?.id ?? "secular";
  return serializeAdminPromptCsv([{
    promptText: "Replace this example with your prompt text",
    level: 1,
    categoryId,
    status: "active",
  }]);
}
