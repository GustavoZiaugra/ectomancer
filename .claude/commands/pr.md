Create a pull request for the current branch following this workflow:

1. Run `/check` to verify code quality — stop and fix any issues before proceeding.
2. Run `/test` to verify all tests pass — stop and fix any failures before proceeding.
3. Review `git diff main...HEAD` to understand all changes.
4. Create the PR with `gh pr create` using:
   - A short, descriptive title (under 70 characters) with a conventional commit prefix (`feat:`, `fix:`, `refactor:`, `chore:`, etc.)
   - A body with a brief summary and a markdown test-plan checklist
   - Do NOT add a `Co-Authored-By` trailer

Return the PR URL when done.
