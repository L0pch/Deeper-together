import type { PromptLevel } from "@/types/game";

export type AdminPromptStatus = "all" | "active" | "inactive" | "archived";
export type AdminPromptStateAction = "activate" | "deactivate" | "archive" | "restore";

export type AdminPromptCategory = {
  id: string;
  label: string;
  isActive: boolean;
};

export type AdminPromptTag = {
  id: string;
  name: string;
  slug: string;
  isActive: boolean;
};

export type AdminPromptTransferStatus = "active" | "inactive" | "archived";

export type AdminPromptTransferRow = {
  promptText: string;
  level: PromptLevel;
  categoryId: string;
  tags: string[];
  status: AdminPromptTransferStatus;
};

export type AdminPromptImportResult = {
  total: number;
  imported: number;
  skipped: number;
};

export type AdminPrompt = {
  id: string;
  promptText: string;
  level: PromptLevel;
  categoryId: string;
  categoryLabel: string;
  isActive: boolean;
  archivedAt: string | null;
  createdAt: string;
  updatedAt: string;
  tags: AdminPromptTag[];
};

export type AdminPromptCatalog = {
  prompts: AdminPrompt[];
  categories: AdminPromptCategory[];
  tags: AdminPromptTag[];
  total: number;
};

export type AdminPromptFilters = {
  search: string;
  level: PromptLevel | null;
  categoryId: string | null;
  status: AdminPromptStatus;
};

export type AdminPromptInput = {
  id?: string;
  promptText: string;
  level: PromptLevel;
  categoryId: string;
  tagIds: string[];
};

export type AdminTagInput = {
  id?: string;
  name: string;
  slug: string;
};
