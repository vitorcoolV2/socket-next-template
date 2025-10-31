/**
 * Validates input options against a schema.
 * @param {Object} options - Input options.
 * @param {Joi.Schema} schema - Validation schema.
 * @returns {Object} Validated options.
 * @throws {Error} If validation fails.
 */
export function validateOptions(options, schema) {
    const { error, value } = schema.validate(options);
    if (error) {
        throw new Error(`Invalid options: ${error.message}`);
    }
    return value;
}

const DEFAULT_MESSAGE_STATS = {
    firstMessageAt: null,
    lastMessageAt: null,
    sent: 0,
    unread: 0,
    pending: 0,
    delivered: 0,
    read: 0,
};

export function buildDefaultConversation(userId, otherPartyId, userName = null, otherPartyName = null) {
    return {
        userId,
        userName,
        otherPartyId,
        otherPartyName,
        types: [],
        startedAt: null,
        lastMessageAt: null,
        outgoing: { ...DEFAULT_MESSAGE_STATS },
        incoming: { ...DEFAULT_MESSAGE_STATS },
        metadata: null,
        /*   _perspective: userId === otherPartyId ? 'self' : 'other',
           _hasMessages: false,
           _isDefault: true,*/
    };
}


/**
 * Processes a row from the database query into a structured conversation object.
 * @param {Object} row - Database row.
 * @param {string} userId - Current user ID.
 * @param {Object} userNamesMap - Map of user IDs to names.
 * @returns {Object} Structured conversation object.
 */
export function processConversationRow(row, userId, userNamesMap) {
    const isCurrentUserSender = row.senderId === userId;
    const basePath = isCurrentUserSender ? 'user' : 'other';

    return {
        userId: row.senderId,
        userName: userNamesMap[row.senderId] || null,
        otherPartyId: row.recipientId,
        otherPartyName: userNamesMap[row.recipientId] || null,
        types: row.types || [],
        startedAt: row.firstMessageAt ? new Date(row.firstMessageAt).getTime() : null,
        lastMessageAt: row.lastMessageAt ? new Date(row.lastMessageAt).getTime() : null,
        outgoing: {
            firstMessageAt: row.firstMessageAt ? new Date(row.firstMessageAt).getTime() : null,
            lastMessageAt: row[`${basePath}_out_lastMessageAt`] ? new Date(row[`${basePath}_out_lastMessageAt`]).getTime() : null,
            sent: parseInt(row[`${basePath}_out_sentCount`]) || 0,
            pending: parseInt(row[`${basePath}_out_pendingCount`]) || 0,
            delivered: parseInt(row[`${basePath}_out_deliveredCount`]) || 0,
            unread: parseInt(row[`${basePath}_out_unreadCount`]) || 0,
            read: parseInt(row[`${basePath}_out_readCount`]) || 0,
        },
        incoming: {
            firstMessageAt: row.firstMessageAt ? new Date(row.firstMessageAt).getTime() : null,
            lastMessageAt: row[`${basePath}_in_lastMessageAt`] ? new Date(row[`${basePath}_in_lastMessageAt`]).getTime() : null,
            sent: parseInt(row[`${basePath}_in_sentCount`]) || 0,
            unread: parseInt(row[`${basePath}_in_unreadCount`]) || 0,
            pending: parseInt(row[`${basePath}_in_pendingCount`]) || 0,
            delivered: parseInt(row[`${basePath}_in_deliveredCount`]) || 0,
            read: parseInt(row[`${basePath}_in_readCount`]) || 0,
        },
        ...(row.metadata ? { metadata: row.metadata } : {}),
        _perspective: row.senderId === userId ? 'self' : 'other',
        _hasMessages: true,
        _isDefault: false,
    };
}


/**
 * Generates SQL fields for message statistics.
 * @param {string} filterField - Field to filter by (e.g., sender_id).
 * @param {string} prefix - Prefix for output fields.
 * @param {string} direction - Message direction (outgoing/incoming).
 * @returns {string[]} SQL fields.
 */
export function getMessageStats2(filterField, prefix, direction) {
    return [
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}') AS "${prefix}sentCount"`,
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}' AND read_at IS NULL AND status IN ('sent', 'delivered')) AS "${prefix}unreadCount"`,
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}' AND read_at IS NOT NULL) AS "${prefix}readCount"`,
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}' AND status = 'pending') AS "${prefix}pendingCount"`,
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}' AND status IN ('sent', 'delivered')) AS "${prefix}deliveredCount"`,
        `MAX(created_at) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}') AS "${prefix}lastMessageAt"`,
    ];
}
/**
 * Generates SQL fields for message statistics.
 * @param {string} filterField - Field to filter by (e.g., sender_id).
 * @param {string} prefix - Prefix for output fields.
 * @param {string} direction - Message direction (outgoing/incoming).
 * @returns {string[]} SQL fields.
 */
export function getMessageStats(filterField, prefix, direction) {
    return [
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}') AS "${prefix}sentCount"`,
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}' AND read_at IS NULL AND status IN ('sent', 'delivered')) AS "${prefix}unreadCount"`,
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}' AND read_at IS NOT NULL) AS "${prefix}readCount"`,
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}' AND status = 'pending') AS "${prefix}pendingCount"`,
        `COUNT(*) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}' AND status IN ('sent', 'delivered')) AS "${prefix}deliveredCount"`,
        `MAX(created_at) FILTER (WHERE ${filterField} = $1 AND direction = '${direction}') AS "${prefix}lastMessageAt"`,
    ];
}