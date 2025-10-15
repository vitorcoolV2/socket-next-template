

# Real-Time Messaging with Next.js and Socket.IO

**A full-stack real-time chat application built with Next.js, Socket.IO, and Prisma.**

---

## Overview

This project combines **Next.js** for the frontend and API backend with **Socket.IO** for real-time communication. It supports features like live chat, active user tracking, and persistent message storage using PostgreSQL.

Key technologies used:
- **Next.js**: For building the frontend and API routes.
- **Socket.IO**: For real-time communication.
- **Prisma**: For database management with PostgreSQL.
- **TypeScript**: For type-safe development.
- **Tailwind CSS**: For styling the frontend.

---

## Features

- **Real-Time Chat**: Send and receive messages instantly.
- **Active User Tracking**: See who is online in real-time.
- **Persistent Messages**: Messages are stored in a PostgreSQL database.
- **Authentication**: Secure user authentication using Clerk or JWT.
- **Responsive UI**: A modern and responsive design using Tailwind CSS.

---

## Getting Started

### Prerequisites

- **Node.js**: v20.x or higher.
- **PostgreSQL**: A running PostgreSQL instance.
- **Redis** (optional): For scaling Socket.IO.

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/vitorcoolV2/socket-next-template.git
   cd socket-next-template
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Set up environment variables:
   ```bash
   cp .env.example .env
   ```
   Update the `.env` file with your database credentials and other required settings.

4. Run database migrations (if using Prisma):
   ```bash
   npx prisma migrate dev
   ```

5. Start the services:
   - **Socket.IO Server**:
     ```bash
     npm run io
     ```
   - **Next.js Application**:
     ```bash
     npm run dev
     ```

---

## Usage

- Access the Next.js application at `http://localhost:3000`.
- The Socket.IO server runs at `http://localhost:3001`.

---

## Debugging

Both services support debugging using the Node.js Inspector API:
- **Socket.IO Server**: Debugger listens on `ws://127.0.0.1:9229`.
- **Next.js App**: Debugger listens on `ws://127.0.0.1:9230`.

For more details, see the [Node.js Inspector Documentation](https://nodejs.org/en/docs/inspector).

---

## Scripts

Here are the available scripts in this project:

| Script       | Purpose                                   |
|--------------|-------------------------------------------|
| `npm run io` | Start the Socket.IO server.               |
| `npm run dev`| Start the Next.js development server.     |
| `npm run build` | Build the Next.js application.         |
| `npm run start` | Start the Next.js production server.    |
| `npm run lint`  | Check for linting errors.               |
| `npm run test`  | Run Jest tests.                         |

---

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository.
2. Create a new branch for your feature or bug fix:
   ```bash
   git checkout -b feature-name
   ```
3. Commit your changes:
   ```bash
   git commit -m "Add feature or fix"
   ```
4. Push your branch:
   ```bash
   git push origin feature-name
   ```
5. Submit a pull request.

For more details, see our [Contributing Guidelines](CONTRIBUTING.md).

---

## License

This project is licensed under the [MIT License](LICENSE).

