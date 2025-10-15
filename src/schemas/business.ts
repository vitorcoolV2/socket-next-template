import { z } from 'zod';
import { BaseSchema } from './base';

export const categoryList = [
  'ELECTRONICS',
  'CLOTHING',
  'FOOD',
  'BOOKS',
] as const;
export const statusList = ['PENDING', 'SHIPPED', 'DELIVERED'] as const;

export type Category = (typeof categoryList)[number];
export type Status = (typeof statusList)[number];

// Generic schema creators
const createResourceSchema = <T extends z.ZodRawShape>(fieldsShape: T) =>
  BaseSchema.extend(fieldsShape);

// Product Schema
const productFields = {
  name: z.string().min(1).max(100),
  category: z.enum(categoryList), // Match Prisma's Category enum
  price: z.number().positive(),
  inStock: z.boolean(),
  lastUpdated: z.date(),
};

export const ProductSchema = createResourceSchema(productFields);

// Order Item Schema
const orderItemFields = {
  productId: z.uuid(),
  quantity: z.number().int().positive(),
  notes: z.string().nullable().optional(), // Allow null to match Prisma
  orderId: z.uuid(), // Add orderId to match Prisma
};

export const OrderItemSchema = createResourceSchema(orderItemFields);

// Order Schema
const orderFields = {
  status: z.enum(statusList), // Match Prisma's Status enum
  items: z.array(OrderItemSchema), // Use OrderItemSchema instead of orderItemFields
  totalAmount: z.number().positive(),
  customerId: z.uuid(), // Add customerId to match Prisma
};

export const OrderSchema = createResourceSchema(orderFields);

// Customer Schema
const customerFields = {
  name: z.string().min(1),
  email: z.email(),
  loyaltyPoints: z.number().int().nonnegative(),
  lastVisit: z.date(),
};

export const CustomerSchema = createResourceSchema(customerFields);

// API Request Schemas
export const ResourceSchemas = {
  product: ProductSchema,
  order: OrderSchema,
  customer: CustomerSchema,
} as const;

export type ResourceTypes = keyof typeof ResourceSchemas;

// Type exports
export type Product = z.infer<typeof ProductSchema>;
export type Order = z.infer<typeof OrderSchema>;
export type Customer = z.infer<typeof CustomerSchema>;
export type OrderItem = z.infer<typeof OrderItemSchema>;
