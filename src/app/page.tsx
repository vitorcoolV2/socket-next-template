// app/page.tsx
import Link from 'next/link';

export default function HomePage() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gray-100 p-4">
      <h1 className="text-3xl font-bold text-gray-800 mb-4">
        Welcome to the Chat App
      </h1>
      <p className="text-lg text-gray-600 mb-6">
        Sign in to start chatting in real-time with other users!
      </p>
      <Link
        href="/chat"
        className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
      >
        Go to Chat
      </Link>
    </div>
  );
}
