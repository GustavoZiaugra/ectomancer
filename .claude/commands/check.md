Run all code quality checks for this project in sequence and report the results:

1. `mix compile --warnings-as-errors` — must produce zero warnings
2. `mix format --check-formatted` — must produce no diff
3. `mix credo` — must produce zero issues

If any step fails, explain what needs to be fixed and offer to fix it.
