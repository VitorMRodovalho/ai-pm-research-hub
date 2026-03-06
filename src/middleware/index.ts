import { defineMiddleware } from "astro:middleware";

export const onRequest = defineMiddleware(async (context, next) => {
  // Auth is handled client-side in each page
  // Server middleware disabled — Supabase JS v2 uses localStorage, not cookies
  return next();
});
