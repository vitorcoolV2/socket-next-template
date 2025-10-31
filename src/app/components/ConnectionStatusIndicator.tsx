'use client';

import React from 'react';
import { useSocket } from '../context/SocketContext';

export const ConnectionStatusIndicator = () => {
    const { isConnected, isAuthenticated, socket } = useSocket();

    // Map connection status to colors
    const getStatusColor = () => {
        if (!isConnected) return 'bg-red-500'; // Red for disconnected

        if (isAuthenticated) return 'bg-blue-500'; // Blue for authenticated

        return 'bg-green-500'; // Green for connected but not authenticated
    };

    // Map connection status to descriptive text
    const getStatusText = () => {
        if (!isConnected) return 'Disconnected from server';

        if (isAuthenticated) return 'Authenticated with server';

        return 'Connected to server';
    };

    const handleClick = (event: React.MouseEvent | React.KeyboardEvent) => {
        if (event.type === 'keydown' && (event as React.KeyboardEvent).key !== 'Enter') return;

        if (!isConnected && socket) {
            // Reconnect if disconnected
            socket.connect();
        } else if (isConnected && socket) {
            // Disconnect if connected
            socket.disconnect();
        }
    };

    const actionLabel = !isConnected ? 'Reconnect' : 'Disconnect';

    return (
        <span
            className={`inline-block w-3 h-3 rounded-full ${getStatusColor()} cursor-pointer`}
            title={getStatusText()}
            onClick={handleClick}
            onKeyDown={handleClick}
            role="button"
            tabIndex={0}
            aria-label={actionLabel}
        ></span>
    );
};

export default ConnectionStatusIndicator;