# Contributing to SemanticWeb.jl

Thank you for your interest in contributing! This guide will help you get started.

## Quick Links

- **[README.md](README.md)** - User documentation and API reference
- **[CLAUDE.md](CLAUDE.md)** - Comprehensive development guide (architecture, patterns, how-tos)
- **[TEST_FAILURES.md](TEST_FAILURES.md)** - Known issues and how to fix them

## Getting Started

### 1. Setup Development Environment

```bash
# Clone the repository
git clone https://github.com/yourusername/SemanticWeb.jl.git
cd SemanticWeb.jl

# Start Julia with the project
julia --project=.

# Install dependencies
using Pkg
Pkg.instantiate()

# Run tests
Pkg.test()
```

### 2. Understand the Architecture

Read **[CLAUDE.md](CLAUDE.md)** for:
- System overview and architecture
- Core design principles
- Component descriptions
- How to extend the library
- Common pitfalls to avoid

### 3. Pick an Issue

Good first issues:
- **Fix language-tagged literal serialization** (see [TEST_FAILURES.md](TEST_FAILURES.md))
- Add new SPARQL features (aggregations, property paths)
- Add new SHACL constraints
- Improve documentation
- Add examples

## Development Workflow

### Making Changes

1. **Create a branch**
```bash
git checkout -b feature/your-feature-name
```

2. **Make your changes**
- Follow Julia style conventions
- Use meaningful variable names
- Add comments for complex logic

3. **Write tests**
```julia
# test/component/test_feature.jl
@testset "Your Feature" begin
    store = RDFStore()
    # ... test code ...
    @test expected_result
end
```

4. **Run tests**
```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

5. **Update documentation**
- Update README.md if adding user-facing features
- Update CLAUDE.md if changing architecture
- Add docstrings to new functions

### Code Style

Follow Julia conventions:
- **Function names:** `lowercase_with_underscores`
- **Type names:** `CamelCase`
- **Constants:** `UPPERCASE` or `CamelCase`
- **Mutation:** Functions ending in `!` modify arguments
- **Private functions:** Prefix with `_underscore`

Example:
```julia
"""
    add!(store::RDFStore, triple::Triple) -> Nothing

Add a triple to the store, updating all indexes.
"""
function add!(store::RDFStore, triple::Triple)
    # Implementation
end
```

### Testing Guidelines

1. **Test one thing per @testset**
2. **Use descriptive names**
3. **Test edge cases** (empty data, missing values, errors)
4. **Test error conditions** with `@test_throws`
5. **Keep tests independent** (don't rely on test order)

Example:
```julia
@testset "SPARQL FILTER with numeric comparison" begin
    store = RDFStore()

    # Setup
    alice = IRI("http://example.org/alice")
    add!(store, alice, age_pred, Literal("30", XSD.integer))

    # Execute
    query_str = """
        SELECT ?person WHERE {
            ?person <http://example.org/age> ?age .
            FILTER (?age > 25)
        }
    """
    result = query(store, parse_sparql(query_str))

    # Assert
    @test length(result) == 1
    @test result[1][:person] == alice
end
```

## Common Tasks

### Adding a SPARQL Feature

See **[CLAUDE.md](CLAUDE.md)** section "Adding a New SPARQL Feature" for step-by-step guide.

### Adding a SHACL Constraint

See **[CLAUDE.md](CLAUDE.md)** section "Adding a New SHACL Constraint" for step-by-step guide.

### Fixing a Bug

1. **Find or create an issue**
2. **Write a failing test** that demonstrates the bug
3. **Fix the bug**
4. **Verify the test passes**
5. **Submit a pull request**

### Improving Documentation

Documentation improvements are always welcome:
- Fix typos
- Add examples
- Clarify confusing sections
- Add missing API documentation
- Update guides with new features

## Pull Request Process

1. **Ensure tests pass**
```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

2. **Update CHANGELOG.md** (if not present, create it)

3. **Create pull request** with:
   - Clear title describing the change
   - Description of what changed and why
   - Link to related issues
   - Screenshots/examples if relevant

4. **Address review feedback**

## Working with Known Issues

See **[TEST_FAILURES.md](TEST_FAILURES.md)** for:
- Detailed analysis of failing tests
- Root causes
- Potential solutions
- Investigation steps

High-priority fixes needed:
1. Language-tagged literal serialization (Serd.jl API issue)
2. Blank node round-trip (minor issue)

## Questions?

- **General questions:** Open a GitHub issue with the "question" label
- **Bug reports:** Open a GitHub issue with the "bug" label
- **Feature requests:** Open a GitHub issue with the "enhancement" label
- **Claude Code specific:** See [CLAUDE.md](CLAUDE.md)

## Code of Conduct

Be respectful and constructive:
- Welcome newcomers
- Provide helpful feedback
- Focus on the code, not the person
- Keep discussions on-topic

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see LICENSE file).

## Acknowledgments

Contributors will be listed in:
- README.md (Contributors section)
- Git commit history
- CHANGELOG.md

---

Thank you for contributing to SemanticWeb.jl! 🎉
