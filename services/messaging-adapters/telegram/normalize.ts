export interface TelegramUpdate {
  update_id: number;
  message?: {
    message_id: number;
    from?: { id: number; username?: string; first_name?: string };
    chat: { id: number; type: string };
    date: number;
    text?: string;
  };
}

export interface NormalizedMessage {
  platform: 'telegram';
  platform_user_id: string;
  chat_id: string;
  platform_message_id: string;
  text: string;
  received_at: string;
}

export function normalizeInbound(update: TelegramUpdate): NormalizedMessage | null {
  const message = update.message;
  if (!message || !message.from || typeof message.text !== 'string') {
    return null;
  }

  return {
    platform: 'telegram',
    platform_user_id: String(message.from.id),
    chat_id: String(message.chat.id),
    // update_id is globally unique per bot; message.message_id is only unique within a
    // single chat, so update_id is the correct key for webhook_events dedup.
    platform_message_id: String(update.update_id),
    text: message.text,
    received_at: new Date(message.date * 1000).toISOString(),
  };
}
