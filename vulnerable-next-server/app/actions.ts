"use server";

/**
 * Simple echo action - returns the input message.
 * Useful for testing RSC argument serialization.
 */
export async function echo(message: string): Promise<{ message: string; timestamp: number }> {
  return {
    message,
    timestamp: Date.now(),
  };
}

/**
 * Ping action - confirms server is reachable.
 * Returns server time and Node version.
 */
export async function ping(): Promise<{
  pong: true;
  timestamp: number;
  nodeVersion: string;
}> {
  return {
    pong: true,
    timestamp: Date.now(),
    nodeVersion: process.version,
  };
}

/**
 * Form submission action - handles form data.
 * Useful for testing multipart form handling (same path as exploit).
 */
export async function submitForm(formData: FormData): Promise<{
  success: boolean;
  received: Record<string, string>;
}> {
  const received: Record<string, string> = {};
  formData.forEach((value, key) => {
    received[key] = String(value);
  });

  return {
    success: true,
    received,
  };
}

/**
 * Reflect action - returns first argument as-is.
 * Useful for data exfiltration testing (returns whatever you pass).
 */
export async function reflect(data: string): Promise<{ data: string }> {
  return { data };
}
