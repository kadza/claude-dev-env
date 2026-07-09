## Node + TypeScript

Prefer TypeScript over plain JavaScript. Type new code; don't reach for `any` to silence the compiler.

Use ES modules (`import`/`export`), not CommonJS `require`.

Run `npx tsc --noEmit` to typecheck and `npx vitest` to run tests. Both should pass before you consider a
change done.

Use the project's existing package manager and scripts (`package.json`) rather than introducing new tools.
