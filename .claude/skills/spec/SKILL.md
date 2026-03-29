---
name: spec
description: Execute a spec file from Claude Chat (Product Leader)
user_invocable: true
---

Execute the spec file at path $ARGUMENTS.

Workflow:
1. Read the entire spec file
2. List all deliverables and their execution order
3. For each deliverable:
   a. Check prerequisites (RPCs, tables, columns exist)
   b. Execute (migration, code change, EF update)
   c. Verify against the spec's checklist
4. After all deliverables: `npx astro build` + `npm test`
5. Deploy if tests pass
6. Report results as a table matching the spec's verification checklist
7. Commit with descriptive message referencing the GC number

If a deliverable fails, stop and report — don't skip to the next.
