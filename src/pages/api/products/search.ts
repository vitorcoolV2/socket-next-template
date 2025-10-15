import { z } from 'zod';
import { createApiHandler } from '@/lib/api-handler';
import { ProductSchema } from '@/schemas/business';
import { prisma } from '@/lib/prisma';
import { wrappers } from '@/lib/schema-utils';
import { Category } from '@prisma/client'; // Import Prisma's generated `Category` enum

const defaultPage = 1;
const defaultLimit = 10;

// POST /api/products/search
export default createApiHandler({
  resource: 'product',
  operation: 'search',
  validateInput: z.object({
    query: z.string().optional(),
    category: z.enum(Category).optional(),
    priceRange: z
      .object({
        min: z.number().optional(),
        max: z.number().optional(),
      })
      .optional(),
    inStock: z.boolean().optional(),
    page: z.number().int().positive().default(1),
    limit: z.number().int().positive().max(100).default(10),
  }),
  handler: async ({
    query,
    category,
    priceRange,
    inStock,
    page = defaultPage,
    limit = defaultLimit,
  }) => {
    const where = {
      ...(query && {
        OR: [
          { name: { contains: query, mode: 'insensitive' } },
          { description: { contains: query, mode: 'insensitive' } },
        ],
      }),
      ...(category && { category: { equals: category } }), // Fix for Prisma's `EnumCategoryFilter`
      ...(inStock !== undefined && { inStock }),
      ...(priceRange?.min && { price: { gte: priceRange.min } }),
      ...(priceRange?.max && { price: { lte: priceRange.max } }),
    };

    const [items, total] = await Promise.all([
      prisma.product.findMany({
        where,
        skip: (page - 1) * limit,
        take: limit,
      }),
      prisma.product.count({ where }),
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
