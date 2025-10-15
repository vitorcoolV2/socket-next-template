import { NextApiRequest, NextApiResponse } from 'next';
import { z, treeifyError } from 'zod';
import { APIResponse, APIOperations } from '../schemas/base';
import { ResourceSchemas, ResourceTypes } from '../schemas/business';
// TODO (personalized?) import { UserSchema } from '../schemas/user';

type HandlerConfig<T extends ResourceTypes, TInput, TOutput> = {
  resource: T;
  operation: (typeof APIOperations)[keyof typeof APIOperations];
  validateInput?: z.ZodSchema<TInput>;
  handler: (data: TInput) => Promise<TOutput>;
};

export function createApiHandler<
  T extends ResourceTypes,
  TInput = unknown,
  TOutput = unknown,
>(config: HandlerConfig<T, TInput, TOutput>) {
  const { resource, operation, validateInput, handler } = config;
  return async (
    req: NextApiRequest,
    res: NextApiResponse<APIResponse<TOutput>>
  ) => {
    try {
      // Validate request method
      const methodMap = {
        [APIOperations.CREATE]: 'POST',
        [APIOperations.READ]: 'GET',
        [APIOperations.UPDATE]: 'PUT',
        [APIOperations.DELETE]: 'DELETE',
        [APIOperations.LIST]: 'GET',
        [APIOperations.SEARCH]: 'GET',
      };

      if (req.method !== methodMap[operation]) {
        return res.status(405).json({
          success: false,
          error: {
            code: '405',
            message: `Method ${req.method} not allowed`,
          },
        });
      }

      // Parse and validate input
      let data = req.method === 'GET' ? req.query : req.body;

      if (validateInput) {
        data = validateInput.parse(data);
      }

      // Execute handler
      const result = await handler(data);

      // Validate output with resource schema
      const schema = ResourceSchemas[resource];
      const validatedResult = Array.isArray(result)
        ? result.map((item) => schema.parse(item))
        : schema.parse(result);

      return res.status(200).json({
        success: true,
        data: validatedResult as TOutput,
      });
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({
          success: false,
          error: {
            code: '400',
            message: 'Validation error',
          },
          metadata: { details: treeifyError(error) },
        });
      }

      console.error(`API Error [${resource}/${operation}]:`, error);
      return res.status(500).json({
        success: false,
        error: {
          code: '500',
          message: 'Internal server error',
        },
      });
    }
  };
}
