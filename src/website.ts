import { z } from 'zod';

export const WebsiteSchema = z.object({
  id: z.number().int().positive(),
  name: z.string().min(1).max(100),
  url: z.url().regex(/^https?:\/\//),
  role: z.enum(['admin', 'user', 'guest']),
  config: z.string().refine(
    (val) => {
      try {
        JSON.parse(val);
        return true;
      } catch {
        return false;
      }
    },
    { message: 'Must be a valid JSON string' }
  ),
});
