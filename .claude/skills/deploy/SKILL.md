---
name: deploy
description: Build, test, and deploy the platform to production
user_invocable: true
---

Deploy the platform to production. Steps:

1. Run `npx astro build` — must pass with 0 errors
2. Run `npm test` — must have 0 failures
3. Check for legacy URLs: `grep -rn "platform.ai-pm-research-hub.workers.dev" src/ --include="*.ts" --include="*.astro" | grep -v middleware`
4. If clean: `npx wrangler deploy`
5. Verify: `curl -sI https://nucleoia.vitormr.dev/ | head -3`
6. If Edge Functions changed: `supabase functions deploy <name> --no-verify-jwt` for each changed EF
7. Report deploy status with version ID

If any step fails, stop and report the error.
