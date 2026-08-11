import assert from "node:assert/strict";
import test from "node:test";

import { parseGoogleSheetPromptValues } from "../../src/lib/admin/prompt-csv.ts";

test("Google Sheet imports ignore fully blank rows without breaking inherited values", () => {
  const rows = parseGoogleSheetPromptValues([
    ["prompt_text", "level", "category", "status"],
    ["First prompt", "1", "secular", "active"],
    [],
    ["", "", "", ""],
    ["Second prompt", "2", "", ""],
  ]);

  assert.deepEqual(rows, [
    {
      promptText: "First prompt",
      level: 1,
      categoryId: "secular",
      status: "active",
    },
    {
      promptText: "Second prompt",
      level: 2,
      categoryId: "secular",
      status: "active",
    },
  ]);
});

test("Google Sheet imports still identify the original row for partial rows", () => {
  assert.throws(
    () => parseGoogleSheetPromptValues([
      ["prompt_text", "level", "category", "status"],
      [],
      ["", "1", "secular", "active"],
    ]),
    /Row 3: prompt_text must contain 1 to 500 plain-text characters\./,
  );
});
