# Agents.md

Goal: guide the agent to architect, implement, test, and refactor code with emphasis on maintainability, readability for agents, change safety, and automated feedback.

## Principles

- Write code to be read, changed, and validated by both agents and humans.
- Prefer small, explicit, testable units that are searchable with `grep`/`rg`.
- Do not implement only the happy path. Consider errors, observability, security, timeouts, retries, idempotency, and regression tests.
- Do not perform broad rewrites unless necessary. Change the smallest coherent unit that solves the problem.
- Preserve existing behavior unless the requested change explicitly requires a breaking change.
- Every relevant change must include a test, validation, or an objective explanation of why local validation is not possible.

## Agent workflow

Before coding:

- Restate the objective, acceptance criteria, non-goals, constraints, and risks.
- Explore the affected code and tests without modifying files.
- Present the smallest coherent implementation plan.
- For complex or high-risk work, create or update an ExecPlan according to `.agent/PLANS.md`.
- Do not implement until the plan contains an objective validation strategy.
- Read the project instructions, README, build/test scripts, and files related to the task.
- Use lexical search (`rg`, `grep`, `find`) to locate responsibilities, names, tests, and entry points.
- Identify the smallest affected architectural boundary.
- Check existing conventions before creating a new pattern.
- Consider impacts on APIs, database, jobs, queues, authentication, cache, logs, observability, and tests.

During implementation:

- Make small, cohesive changes.
- Prefer adding to or adjusting existing modules instead of creating premature generic abstractions.
- Do not duplicate logic. Extract shared behavior into a specific function, class, module, or service.
- Do not introduce global dependencies, mutable global state, or scattered configuration.
- Preserve backward compatibility when possible.
- Do not ignore lint, type, or test failures.
- Add or update tests before completing each behavioral change.
- Run focused tests after each slice
- Keep commits atomic and independently valid.

When finishing:

- Run the project’s formatting, linting, type-checking, and test commands.
- If the commands are unknown, look for them in `README`, `Makefile`, `package.json`, `pyproject.toml`, `Cargo.toml`, `Gemfile`, `go.mod`, or equivalent files.
- If validation cannot be executed, state the exact command that should be run and the reason for the limitation.
- Review the diff before concluding. Remove dead code, unused imports, temporary logs, and **obvious comments**.

## Structure

- Each module must have a clear responsibility and one primary reason to change.
- Separate domain, application, infrastructure, and interface layers when the project already follows that pattern.
- Do not mix business rules with external I/O, framework code, raw SQL, HTTP calls, queues, or UI details.
- Prefer dependencies injected through constructors, parameters, or explicit providers.
- Encapsulate third-party libraries behind thin interfaces owned by the project.
- Centralize configuration in dedicated objects, files, or modules. Do not scatter magic strings, URLs, model names, feature flags, or operational constants.
- Avoid god files, god classes, generic `manager`/`service` objects, and modules that accumulate responsibilities without a clear boundary.

## Code Style

- Functions should be short, with one main intention and one dominant level of abstraction.
- Files should remain small enough for an agent tool to read in full. Use fewer than 500 lines as a reference; ideally 200–300 lines when feasible.
- Split files by responsibility, not by temporary convenience.
- Avoid deep nesting. Use guard clauses, early returns, function extraction, and pattern matching when appropriate.
- Use at most two relevant indentation levels inside a function. If more are needed, refactor.
- Prefer simple composition over complex hierarchies.
- Avoid applying abstractions or removing duplicates prematurely (premature DRY).
- Use specific, descriptive, unique, and searchable names.
- Avoid generic names such as `data`, `payload`, `info`, `handler`, `processor`, `manager`, `service`, or `helper`, unless they are qualified by the domain.
- Prefer names that reveal intent and reduce irrelevant `rg` results.
- Name code after the business concept or actual technical responsibility: `InvoiceTotalCalculator`, `UserRegistrationValidator`, `PaymentProviderWebhookVerifier`.
- Do not use internal abbreviations without context.
- Test names must describe behavior, scenario, and expected result.

## Types and contracts

- Use explicit types for inputs, outputs, data structures, and relevant states.
- Avoid `any`, `unknown` without narrowing, generic maps, loose dictionaries, and structures without contracts.
- Model invalid states as impossible whenever the language allows it.
- Use enums, unions, value objects, schemas, or validators to represent domain states.
- Do not hide type uncertainty with forced casts. Fix the source of the type problem.
- Public APIs must have stable, documented, and tested contracts.

## Comments

- Write comments to explain why something exists, not what the code already shows.
- Preserve useful comments created during refactors; they carry intent, context, and provenance.
- Remove obvious, redundant comments that only translate syntax.
- Use docstrings in public functions, classes, and modules when there is a relevant business rule, contract, side effect, or usage example.
- Include references to issues, tickets, incidents, commits, or upstream limitations when a decision exists because of specific history.
- Update comments and docstrings when changing the corresponding behavior.

## Tests

- Every new business rule must have an automated test.
- Every bug fix must have a regression test that fails before the fix.
- Tests must follow F.I.R.S.T.: fast, independent, repeatable, self-validating, and timely.
- Tests must run headlessly without human intervention.
- The test command must be single, documented, and executable by the agent.
- Use named fakes for external I/O: APIs, databases, filesystems, queues, email, payments, LLMs, and storage.
- Avoid opaque inline mocks. Prefer test doubles with explicit names and behavior.
- Test observable behavior, not fragile internal details.
- If architecture changes, update or add tests at the correct level: unit, integration, contract, or end-to-end.

## Security

- NEVER hardcode credentials, tokens, keys, sensitive URLs, or personal data.
- Use environment variables, a secret manager, or the mechanism already adopted by the project.
- Apply the principle of least privilege.
- Validate authorization on the server; do not rely only on the UI.
- Sanitize inputs used in SQL, shell commands, paths, HTML, Markdown, templates, and external calls.
- Avoid shell injection, path traversal, SSRF, XSS, CSRF, SQL injection, and unsafe deserialization.
- When handling sensitive data, minimize collection, retention, and exposure in logs/tests.

## Resilience and defensive programming

- Configure explicit timeouts for external calls.
- Use retries with backoff only for transient failures and idempotent operations.
- Use circuit breakers or fallbacks when an external provider may degrade the system.
- Respect rate limits and quotas.
- Design jobs and handlers to be idempotent.
- In critical integrations, distinguish temporary failures, permanent failures, and validation failures.
- Do not create infinite retry loops.
- Document consistency, latency, and fallback trade-offs when relevant.

## Approval gates

Do not perform the following without explicit approval:

- Add or replace a production dependency.
- Alter authentication, authorization, billing, cryptography, or secrets.
- Perform destructive database or filesystem operations.
- Access data or systems outside the workspace.
- Change CI, deployment infrastructure, or security controls.
- Deploy or roll back production.
- Disable, skip, weaken, or ignore a required check.

Do not leave durable project decisions only in chat history or agent memory.
