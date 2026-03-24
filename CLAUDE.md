# Claude Code Directives - Python

## Scope
- Priority: `src/` or main project folder
- Ignore: `__pycache__/`, `.venv/`, `.pytest_cache/`, `*.pyc`, `build/`, `dist/`

## Reading
- Check relevance before opening (rg/grep/head or Select-String)
- Read the minimum necessary

## Code
- Change the strict minimum
- Follow PEP8 + typing if already used
- Don't touch imports unnecessarily
- No refactoring outside scope
- Never use `...` in final code

## Async
- Don't introduce asyncio if absent
- Don't mix sync/async

## Tests
- Targeted testing: `pytest -k <test>`
- Don't run the full suite without reason

## Install
- Use `pip install -e .` for local dependencies

## Lint
- Use ruff (preferred)

## Errors
- Read the last 20 useful lines
- Max 2 attempts, then stop and ask

## Responses
- Short, technical
- No variants
- No unnecessary explanations
