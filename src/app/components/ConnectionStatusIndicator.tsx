// src/app/components/ConnectionStatusIndicator.tsx
'use client';

import React from 'react';
import { useSocketContext } from './SocketContext';

const ConnectionStatusIndicator = () => {
    const { connectionStatus, connectSocket, disconnectSocket } = useSocketContext();

    // Map connection status to colors
    const getStatusColor = () => {
        switch (connectionStatus) {
            case 'connected':
                return 'bg-green-500'; // Green for connected
            case 'connecting':
                return 'bg-yellow-500'; // Yellow for connecting
            case 'authenticated':
                return 'bg-blue-500'; // Blue for authenticated
            case 'disconnected':
            default:
                return 'bg-red-500'; // Red for disconnected
        }
    };

    // Determine the click action based on the connection status
    const getClickAction = () => {
        if (['disconnected', 'connecting'].includes(connectionStatus)) {
            return connectSocket;
        }
        if (['connected', 'authenticated'].includes(connectionStatus)) {
            return disconnectSocket;
        }
        return undefined; // No action for intermediate states like "connecting"
    };

    return (
        <span
            className={`inline-block w-3 h-3 rounded-full ${getStatusColor()} cursor-pointer`}
            title={connectionStatus}
            onClick={getClickAction()}
            role="button"
            aria-label={connectionStatus === 'disconnected' ? 'Reconnect' : 'Disconnect'}
        ></span>
    );
};

export default ConnectionStatusIndicator;