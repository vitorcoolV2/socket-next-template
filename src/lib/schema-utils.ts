import { z } from 'zod';

// Common field validators
export const validators = {
  phone: z.string().regex(/^\+?[1-9]\d{1,14}$/, 'Invalid phone number'),
  url: z.string().url('Invalid URL'),
  slug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/, 'Invalid slug format'),
  password: z
    .string()
    .min(8)
    .regex(
      /^(?=.*[A-Za-z])(?=.*\d)/,
      'Password must contain letters and numbers'
    ),
  email: z.string().email('Invalid email format'),
  dateRange: z
    .object({
      start: z.date(),
      end: z.date(),
    })
    .refine(
      (data) => data.start <= data.end,
      'End date must be after start date'
    ),
};

// Schema transformers
export const transformers = {
  addTimestamps: <T extends z.ZodObject<z.ZodRawShape>>(schema: T) =>
    schema.extend({
      createdAt: z.date(),
      updatedAt: z.date(),
    }),

  addSoftDelete: <T extends z.ZodObject<z.ZodRawShape>>(schema: T) =>
    schema.extend({
      deletedAt: z.date().nullable().optional(),
    }),

  addVersion: <T extends z.ZodObject<z.ZodRawShape>>(schema: T) =>
    schema.extend({
      version: z.number().int().positive(),
    }),
};

// Response wrappers
export const wrappers = {
  paginated: <T extends z.ZodTypeAny>(schema: T) =>
    z.object({
      items: z.array(schema),
      total: z.number(),
      page: z.number(),
      pageSize: z.number(),
      hasMore: z.boolean(),
    }),

  withMetadata: <T extends z.ZodTypeAny>(schema: T) =>
    z.object({
      data: schema,
      metadata: z.record(z.string(), z.any()),
    }),
};

// Query builders
export const queryBuilders = {
  pagination: (page: number = 1, limit: number = 10) => ({
    skip: (page - 1) * limit,
    take: limit,
  }),

  orderBy: (field: string, order: 'asc' | 'desc' = 'asc') => ({
    orderBy: { [field]: order },
  }),
};
