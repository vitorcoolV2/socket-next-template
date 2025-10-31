import { z } from 'zod';

export const WebsiteSchema = z.object({
  id: z.number().int().min(1, { message: '"id" must be a positive integer' }),
  url: z.string().url({ message: '"url" must be a valid URL (http or https)' }),
  config: z.string().transform((val, ctx) => {
    try {
      return JSON.parse(val);
    } catch {
      ctx.addIssue({
        code: 'custom',
        message: '"config" must be a valid JSON string',
      });
      return z.NEVER;
    }
  }),
  name: z
    .string()
    .min(1)
    .max(100, { message: '"name" must be 1-100 characters' })
    .optional(),
  role: z.enum(['admin', 'user', 'guest'], {
    message: '"role" must be one of [admin, user, guest]',
  }),
});

export type Website = z.infer<typeof WebsiteSchema>;
