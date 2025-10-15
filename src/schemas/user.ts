import { z } from 'zod';

import { BaseSchema } from './base';

export const UserSchema = BaseSchema.extend({
  name: z.string(),
  email: z.email(),
});
