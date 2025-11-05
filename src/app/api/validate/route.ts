import { NextResponse } from 'next/server';
import { WebsiteSchema } from '@/schemas/website';

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const body = Object.fromEntries(url.searchParams.entries());
    const result = WebsiteSchema.safeParse(body);

    if (!result.success) {
      const errors = result.error.issues.map((issue) => issue.message);
      return NextResponse.json({ errors }, { status: 400 });
    }

    return NextResponse.json({ data: result.data });
  } catch (error: unknown) {
    const errorMessage =
      error instanceof Error ? error.message : 'Unknown error';
    const errors = ['Invalid request body', errorMessage];
    return NextResponse.json({ errors }, { status: 400 });
  }
}

// Explicitly configure the route as static
export const dynamic = 'force-static';