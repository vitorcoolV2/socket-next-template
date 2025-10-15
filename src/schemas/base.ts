import { z } from 'zod';

// Base schema for all entities
export const BaseSchema = z.object({
  id: z.uuid(),
  createdAt: z.date().optional(),
  updatedAt: z.date().optional(),
});

const ErrorSchema = z.object({
  code: z.string(),
  message: z.string(),
  details: z.record(z.string(), z.unknown()).optional(),
});

// Generic CRUD operation names
export const APIOperations = {
  CREATE: 'create',
  READ: 'read',
  UPDATE: 'update',
  DELETE: 'delete',
  LIST: 'list',
  SEARCH: 'search',
} as const;

export type APIOperation = (typeof APIOperations)[keyof typeof APIOperations];

// Generic API endpoint builder
export const buildEndpoint = (resource: string, operation: APIOperation) =>
  `/api/${resource}/${operation}`;

const PaginationShape = {
  page: z.number().int().positive().default(1),
  limit: z.number().int().positive().default(10),
  sort: z.string().optional(),
  order: z.enum(['asc', 'desc']).optional(),
};

// Pagination schema
export const PaginationSchema = z.object(PaginationShape);

// Search params schema
// PaginationSchema is assumed to be defined elsewhere
export const SearchParamsSchema = z
  .object({
    query: z.string().optional(),
    filters: z.record(z.string(), z.any()).optional(),
  })
  .extend(PaginationShape);

// Schema extension as base for API responses. thnak you Q-who you may be
export const APIResponseSchema = <T extends z.ZodTypeAny>(dataType: T) =>
  z.object({
    success: z.boolean(),
    data: dataType.optional(),
    error: ErrorSchema.optional(),
    metadata: z.record(z.string(), z.unknown()).optional(),
  });

// Must be typescript.
export type APIResponse<T> = {
  success: boolean;
  data?: T;
  error?: { code?: string; message?: string; details?: unknown };
  metadata?: Record<string, unknown>;
};

export type PaginationParams = z.infer<typeof PaginationSchema>;
export type SearchParams = z.infer<typeof SearchParamsSchema>;
