---
description: Convert spec test cases into executable C# tests (TDD)
---

# Test Creation Workflow

Convert spec test cases into executable tests. Test agents write ONLY test files.

## CRITICAL: Test Agents Write ONLY Test Files

Never create or modify implementation source files. If tests need types that
don't exist yet, mark tests with appropriate skip attributes.

## SS14 Testing Conventions

### Unit Tests
Location: `Content.Tests/`
Framework: NUnit (`[Test]`, `[TestFixture]`)

```csharp
[TestFixture]
public sealed class RecipeSystemTest : ContentUnitTest
{
    [Test]
    public void TestRecipeValid()
    {
        // arrange
        // act
        // assert
    }
}
```

### Integration Tests
Location: `Content.IntegrationTests/Tests/`
Framework: NUnit with SS14 test helpers

```csharp
[TestFixture]
public sealed class RecipeIntegrationTest
{
    [Test]
    public async Task TestRecipeApplied()
    {
        await using var pair = await PoolManager.GetServerClient();
        var server = pair.Server;

        await server.WaitAssertion(() =>
        {
            // test logic using server.EntMan, server.System<T>(), etc.
        });

        await pair.CleanReturnAsync();
    }
}
```

### Skipping Tests for Unimplemented Dependencies

```csharp
[Test]
[Ignore("Needs _VS/Cooking/RecipeSystem implementation")]
public void TestRecipeCooking()
{
    // test body ready for when impl exists
}
```

## TDD Applicability in SS14

| Area | TDD Feasible? | Notes |
|------|---------------|-------|
| EntitySystems | Yes | Unit test system logic with mock entities |
| Components | Yes | Test serialization, data validation |
| Prototypes | Partial | YAMLLinter validates structure; gameplay testing is manual |
| UI/XAML | No | Manual in-game testing required |
| Maps | No | Visual verification only |
| Networking | Partial | Integration tests can verify networked state |

## Naming Conventions

- Spec tests: direct from spec name
- Edge cases: prefix with `Edge_`
- Error paths: prefix with `Error_`
- Integration: prefix with `Integration_`

## Output

Write test files to `Content.Tests/_VS/` or `Content.IntegrationTests/Tests/_VS/`.

Commit with:
```
:white_check_mark: tests: [system name]

Bead: <bead-id>
```
