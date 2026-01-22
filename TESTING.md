## TDD workflow

We use a simple Red / Green / Refactor loop:

1. **Red**: write a failing test that captures the behavior.
2. **Green**: implement the smallest change to make it pass.
3. **Refactor**: clean up code and tests, keeping all tests green.

Keep tests focused on behavior and deterministic outcomes. Avoid camera or system
integration in unit tests whenever possible.

## Running tests locally

Run the full suite:

```bash
bash run-tests.sh
```

Run a single test (example):

```bash
bash run-tests.sh -only-testing:BrrrrTests/TouchClassifierTests/testTouching_whenFingerVeryClose
```

## TDD watch mode

Watch for changes and re-run tests automatically:

```bash
bash tdd.sh --watch
```

To watch a single test:

```bash
bash tdd.sh --watch -only-testing:BrrrrTests/TouchClassifierTests/testTouching_whenFingerVeryClose
```

Watch mode requires `fswatch`:

```bash
brew install fswatch
```

## Test status table

Run the full suite and print a table of all tests:

```bash
bash test-report.sh
```

If you already have a result bundle, skip the test run:

```bash
bash test-report.sh --skip-run
```

## Test conventions

- Tests live in `BrrrrTests/`.
- Name tests using `test_whenCondition_expectedOutcome`.
- Prefer pure logic and model-layer tests.
- Use `@testable import Brrrr` to access internal types.
- Add the smallest test that describes the behavior you want to ship.

## CI

CI runs `run-tests.sh` on every pull request and on pushes to `main`.
