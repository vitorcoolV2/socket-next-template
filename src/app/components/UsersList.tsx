// components/UserList.tsx
import React, { useEffect, useState } from 'react';
import { useSocket, User } from '../context/SocketContext';

/*interface User {
    userId: string;
    userName: string;
    state: 'disconnected' | 'connected' | 'authenticated' | 'offline';
}*/

interface UserListProps {
    setRecipient: (userId: string) => void;
}

const UserList = ({ setRecipient }: UserListProps) => {
    const { socket, isConnected, isAuthenticated } = useSocket();
    const [users, setUsers] = useState<User[]>([]);
    const [selectedUserId, setSelectedUserId] = useState<string | null>(null); // Add this state

    useEffect(() => {
        if (!socket || !isConnected || !isAuthenticated) return;

        console.log('Requesting users list...');
        socket.emit('getUsers', { states: ['authenticated', 'offline'], limit: 50, offset: 0 });

        const handleUsersList = (fetchedUsers: User[]) => {
            console.log('Received users list:', fetchedUsers);
            setUsers(fetchedUsers);
        };

        const handleUserStateUpdate = (updatedUser: User) => {
            console.log('Received user state update:', updatedUser);
            setUsers((prevUsers) =>
                prevUsers.map((user) => (user.userId === updatedUser.userId ? updatedUser : user))
            );
        };

        socket.on('usersList', handleUsersList);
        socket.on('userStateUpdate', handleUserStateUpdate);

        return () => {
            socket.off('usersList', handleUsersList);
            socket.off('userStateUpdate', handleUserStateUpdate);
        };
    }, [socket, isConnected, isAuthenticated]);

    const handleUserClick = (userId: string) => {
        setSelectedUserId(userId); // Set the selected user
        setRecipient(userId);
    };

    const sortedUsers = [...users].sort((a, b) => {
        if (a.state === 'authenticated' && b.state !== 'authenticated') return -1;
        if (a.state !== 'authenticated' && b.state === 'authenticated') return 1;
        return 0;
    });

    return (
        <div className="border-r border-gray-300 p-4 w-64 bg-white dark:bg-gray-800">
            <h3 className="text-lg font-bold mb-4 dark:text-gray-200">User List</h3>

            {!isConnected || !isAuthenticated ? (
                <p className="text-gray-500 dark:text-gray-400">Connecting to server...</p>
            ) : users.length === 0 ? (
                <p className="text-gray-500 dark:text-gray-400">Loading users...</p>
            ) : (
                <ul className="space-y-2">
                    {sortedUsers.map((user) => (
                        <li
                            key={user.userId}
                            className={`cursor-pointer p-2 rounded transition-colors ${user.userId === selectedUserId
                                ? 'bg-blue-100 dark:bg-blue-900' // Selected style
                                : 'hover:bg-gray-50 dark:hover:bg-gray-700' // Default hover style
                                }`}
                            onClick={() => handleUserClick(user.userId)}
                        >
                            <strong className="font-medium dark:text-gray-200">{user.userName}</strong> -{' '}
                            <span
                                className={`text-xs px-1.5 py-0.5 rounded-full ${user.state === 'authenticated'
                                    ? 'bg-green-200 text-green-800 dark:bg-green-800 dark:text-green-200'
                                    : 'bg-gray-200 text-gray-600 dark:bg-gray-600 dark:text-gray-300'
                                    }`}
                            >
                                {user.state}
                            </span>
                        </li>
                    ))}
                </ul>
            )}
        </div>
    );
};

export default UserList;