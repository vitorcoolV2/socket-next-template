import { prisma } from '../lib/prisma';

// Use Prisma types for better safety
import type { Prisma, Status } from '@prisma/client';

export const ProductDB = {
  async create(data: Prisma.ProductCreateInput) {
    return prisma.product.create({
      data: {
        ...data,
        lastUpdated: new Date(),
      },
    });
  },

  async update(id: string, data: Prisma.ProductUpdateInput) {
    return prisma.product.update({
      where: { id },
      data: {
        ...data,
        lastUpdated: new Date(),
      },
    });
  },

  async getById(id: string) {
    return prisma.product.findUnique({
      where: { id },
    });
  },

  async getAll() {
    return prisma.product.findMany();
  },
};

export const OrderDB = {
  async create(data: Prisma.OrderCreateInput) {
    return prisma.order.create({
      data: {
        ...data,
        items: {
          // Ensure `data.items` is treated as an array before calling `.map`
          create: Array.isArray(data.items)
            ? data.items.map((item) => ({
                quantity: item.quantity,
                notes: item.notes,
                product: { connect: { id: item.productId } },
              }))
            : [],
        },
      },
      include: {
        items: true,
      },
    });
  },

  async updateStatus(id: string, status: Status) {
    return prisma.order.update({
      where: { id },
      data: { status },
      include: {
        items: true,
      },
    });
  },

  async getById(id: string) {
    return prisma.order.findUnique({
      where: { id },
      include: {
        items: true,
      },
    });
  },
};

export const CustomerDB = {
  async create(data: Prisma.CustomerCreateInput) {
    return prisma.customer.create({
      data,
    });
  },

  async update(id: string, data: Prisma.CustomerUpdateInput) {
    return prisma.customer.update({
      where: { id },
      data,
    });
  },

  async updateLoyaltyPoints(id: string, points: number) {
    return prisma.customer.update({
      where: { id },
      data: {
        loyaltyPoints: points,
        lastVisit: new Date(),
      },
    });
  },
};
