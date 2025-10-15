// app/components/Header.tsx
'use client';

import {
  SignInButton,
  SignOutButton,
  SignedIn,
  SignedOut,
} from '@clerk/nextjs';

export default function Header() {
  return (
    <header className="p-4 bg-gray-800 text-white" role="banner">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold">Chat App</h1>
        <nav>
          <SignedIn>
            <SignOutButton redirectUrl="/" aria-label="Sign out">
              Sign Out
            </SignOutButton>
          </SignedIn>
          <SignedOut>
            <SignInButton
              mode="modal"
              forceRedirectUrl="/chat"
              aria-label="Sign in"
            >
              Sign In
            </SignInButton>
          </SignedOut>
        </nav>
      </div>
    </header>
  );
}
