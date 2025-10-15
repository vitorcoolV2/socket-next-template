import { WebsiteSchema } from '../website';
import { z } from 'zod';

describe('WebsiteSchema', () => {
  it('validates correct data', () => {
    const data = {
      id: 1,
      url: 'https://example.com',
      config: '{"key": "value"}',
      name: 'My Site',
      role: 'user' as const,
    };
    const result = WebsiteSchema.safeParse(data);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data).toEqual(data);
    }
  });

  it('rejects invalid data', () => {
    const data = {
      id: 0,
      url: 'invalid-url',
      config: '{invalid: json}',
      name: '',
      role: 'superuser',
    };
    const result = WebsiteSchema.safeParse(data);
    expect(result.success).toBe(false);
    if (!result.success) {
      const errorMessages = result.error.issues.map(
        (issue: z.ZodIssue) => issue.message
      );
      // Updated error messages to match zod's output
      expect(errorMessages).toContain('Too small: expected number to be >0');
      expect(errorMessages).toContain('Invalid URL');
      expect(errorMessages).toContain(
        'Invalid string: must match pattern /^https?:\\/\\//'
      );
      expect(errorMessages).toContain(
        'Too small: expected string to have >=1 characters'
      );
      expect(errorMessages).toContain(
        'Invalid option: expected one of "admin"|"user"|"guest"'
      );
      expect(errorMessages).toContain('Must be a valid JSON string');
    }
  });
});
