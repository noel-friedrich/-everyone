export const CLIENT_UID_STORAGE_KEY = "client_uid_v1";

function randomHex(bytesLength) {
  const bytes = new Uint8Array(bytesLength);
  window.crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

export function generateClientUid() {
  return randomHex(16);
}

export function ensureClientUid() {
  const existing = localStorage.getItem(CLIENT_UID_STORAGE_KEY);
  if (existing) return existing;

  const created = generateClientUid();
  localStorage.setItem(CLIENT_UID_STORAGE_KEY, created);
  return created;
}
