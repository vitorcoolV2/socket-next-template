import { z } from 'zod';
import { createApiHandler } from '@/lib/api-handler';
import { categoryList } from '@/schemas/business';
import { prisma } from '@/lib/prisma';
import { Prisma } from '@prisma/client';

const minBatch = 1;
const maxBatch = 100;

// Define the input schema for the batch create
// Define the input schema for a single item
const ProductInputSchema = z.object({
  name: z.string().min(1).max(100),
  category: z.enum(categoryList), // Match Prisma's Category enum
  price: z.number().positive(),
  inStock: z.boolean(),
});

// Define the batch input schema
const BatchProductSchema = z
  .array(ProductInputSchema)
  .min(minBatch)
  .max(maxBatch);

// Type for a single item
type ProductInputItem = z.infer<typeof ProductInputSchema>;

// Type for the validated input
type BatchProductInput = ProductInputItem[];

// POST /api/products/batch
export default createApiHandler({
  resource: 'product',
  operation: 'create',
  validateInput: z.object({
    items: BatchProductSchema,
  }),
  handler: async ({ items }: { items: BatchProductInput }) => {
    // Explicitly parse items to ensure plain objects
    const parsedItems = BatchProductSchema.parse(items) as ProductInputItem[];

    // Map validated items to Prisma-compatible input
    const data: Prisma.ProductCreateManyInput[] = parsedItems.map((item) => {
      // Ensure item is treated as a plain object
      const { name, category, price, inStock } = item;
      return {
        name,
        category,
        price,
        inStock,
        lastUpdated: new Date(), // Use provided lastUpdated or default to now
      };
    });

    // Create products in bulk with error handling
    try {
      const createdProducts = await prisma.product.createMany({
        data,
      });

      return {
        success: true,
        count: createdProducts.count,
      };
    } catch (error) {
      throw new Error(`Failed to create products: ${(error as Error).message}`);
    }
  },
});
