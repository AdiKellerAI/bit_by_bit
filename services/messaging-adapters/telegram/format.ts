export interface TelegramSendMessagePayload {
  chat_id: string;
  text: string;
}

const TELEGRAM_MAX_MESSAGE_LENGTH = 4096;

export function formatOutbound(chatId: string, text: string): TelegramSendMessagePayload {
  const trimmed =
    text.length > TELEGRAM_MAX_MESSAGE_LENGTH
      ? text.slice(0, TELEGRAM_MAX_MESSAGE_LENGTH - 1) + '…'
      : text;

  return { chat_id: chatId, text: trimmed };
}

export function buildEchoText(inboundText: string): string {
  return `echo: ${inboundText}`;
}
