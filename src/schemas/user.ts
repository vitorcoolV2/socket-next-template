import { z } from 'zod';

import { BaseSchema } from './base';

export const UserSchema = BaseSchema.extend({
  id: z.string(),
  name: z.string(),
  email: z.email(),
});
