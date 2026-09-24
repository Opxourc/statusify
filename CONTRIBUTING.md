# Contributing to Statusify

Thanks for helping improve Statusify.

## Development

1. Fork or clone the repository.
2. Install the project toolchain:
   - `rokit install`
3. Open the project in Roblox Studio or sync it with Rojo as needed.
4. Make focused changes in the relevant files under `src/` and add/update tests when behavior changes.
5. Run the relevant validation before opening a PR.

Typical tooling in this repo:

- `rokit install` installs Rojo, StyLua, Selene, and Wally
- `stylua .` formats Luau files
- `selene .` checks for lint issues
- Use the test scripts in `tests/` for behavior checks when applicable

## Pull Requests

- Keep PRs small and focused on a single change.
- Explain what changed and why.
- Include a brief summary of validation performed.
- If the change affects behavior, note the expected runtime impact.

## Code Style

This project follows Luau/Roblox conventions:

- PascalCase for modules, services, and public API names
- camelCase for local variables and functions
- SCREAMING_SNAKE_CASE for constants
- Keep naming consistent with the existing codebase
- Prefer clear, explicit logic over clever shortcuts
- Use existing patterns for lifecycle management and effect behavior

## Notes

Statusify is intentionally small and infrastructure-focused. Try to keep changes consistent with the current architecture and avoid adding unrelated API surface area.
