import { Product, Order, Customer, Status } from '../schemas/business';

export interface ServerToClientEvents {
  'product:updated': (product: Product) => void;
  'order:status': (order: Order) => void;
  'customer:points': (customer: Customer) => void;
  'sync:error': (error: { message: string; code: string }) => void;
}

export interface ClientToServerEvents {
  'product:update': (product: Partial<Product>) => void;
  'order:create': (order: Omit<Order, 'id' | 'status'>) => void;
  'order:update': (orderId: string, status: Status) => void;
  'customer:update': (customerId: string, data: Partial<Customer>) => void;
}
