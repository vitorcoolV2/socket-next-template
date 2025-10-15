import { NextResponse } from 'next/server';
import { WebsiteSchema } from '@/schemas/website';
import { getIO } from '@/server/socket';

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const result = WebsiteSchema.safeParse(body);
    const io = getIO();

    if (!result.success) {
      const errors = result.error.issues.map((issue) => issue.message);
      io.emit('validationResult', { errors });
      return NextResponse.json({ errors }, { status: 400 });
    }

    io.emit('validationResult', { data: result.data });
    return NextResponse.json({ data: result.data });
  } catch (error: unknown) {
    const errorMessage =
      error instanceof Error ? error.message : 'Unknown error';
    const errors = ['Invalid request body', errorMessage];
    getIO().emit('validationResult', { errors });
    return NextResponse.json({ errors }, { status: 400 });
  }
}
