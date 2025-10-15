import { z } from 'zod';
import { createApiHandler } from '@/lib/api-handler';
import { ProductSchema } from '@/schemas/business';
import { prisma } from '@/lib/prisma';
import { wrappers, queryBuilders } from '@/lib/schema-utils';

const defaultPage = 1;
const defaultLimit = 10;
const defaultMaxLimit = 100;

// GET /api/products
export default createApiHandler({
  resource: 'product',
  operation: 'list',
  validateInput: z.object({
    page: z.number().int().positive().default(1),
    limit: z
      .number()
      .int()
      .positive()
      .max(defaultMaxLimit)
      .default(defaultLimit),
    sortBy: z.string().optional(),
    order: z.enum(['asc', 'desc']).default('asc'),
  }),
  handler: async ({
    page = defaultPage,
    limit = defaultLimit,
    sortBy,
    order,
  }) => {
    const [items, total] = await Promise.all([
      prisma.product.findMany({
        ...queryBuilders.pagination(page, limit),
        ...(sortBy && queryBuilders.orderBy(sortBy, order)),
      }),
      prisma.product.count(),
    ]);

    return wrappers.paginated(ProductSchema).parse({
      items,
      total,
      page,
      pageSize: limit,
      hasMore: page * limit < total,
    });
  },
});
