# Claude Code Development Guide

This document provides context and guidance for Claude Code (or other AI assistants) working on LinkedData.jl.

## System Overview

LinkedData.jl is a **native Julia RDF library** providing:
1. **RDF triple storage** with hexastore indexing
2. **SPARQL query execution** with full parser
3. **SHACL validation** for data quality

### Architecture

```
LinkedData.jl/
├── src/
│   ├── LinkedData.jl          # Main module (exports)
│   ├── rdf/                    # RDF Foundation
│   │   ├── types.jl            # Core types (IRI, Literal, BlankNode, Triple)
│   │   ├── store.jl            # RDFStore with hexastore (SPO, OPS, PSO)
│   │   ├── namespaces.jl       # Common namespaces (RDF, RDFS, XSD, OWL)
│   │   └── serialization.jl    # Serd.jl integration for I/O
│   ├── sparql/                 # SPARQL Query Engine
│   │   ├── types.jl            # Query and pattern types
│   │   ├── executor.jl         # Query execution engine
│   │   └── parser.jl           # SPARQL query string parser
│   └── shacl/                  # SHACL Validation
│       ├── types.jl            # Shape and constraint types
│       └── validator.jl        # Validation engine
└── test/
    ├── runtests.jl             # Main test runner
    ├── rdf/                    # RDF tests (104 tests)
    ├── sparql/                 # SPARQL tests (66 tests)
    └── shacl/                  # SHACL tests (19 tests)
```

## Core Design Principles

### 1. Julia Idioms
- **Multiple dispatch** for polymorphic behavior
- **Mutation convention**: Functions ending in `!` mutate arguments
- **Iterator protocol**: Results implement `Base.iterate`, `Base.length`, `Base.getindex`
- **Type hierarchy**: Abstract types for extensibility

### 2. Hexastore Indexing
The RDFStore uses three indexes for O(1) triple lookups:
```julia
mutable struct RDFStore
    spo::Dict{RDFNode, Dict{IRI, Set{RDFNode}}}  # Subject → Predicate → Objects
    ops::Dict{RDFNode, Dict{IRI, Set{RDFNode}}}  # Object → Predicate → Subjects
    pso::Dict{IRI, Dict{RDFNode, Set{RDFNode}}}  # Predicate → Subject → Objects
end
```

**Query patterns:**
- `?s ?p ?o` → Full scan
- `s ?p ?o` → Use SPO index
- `?s ?p o` → Use OPS index
- `?s p ?o` → Use PSO index
- `s p ?o` → SPO lookup (most efficient)
- `s ?p o` → Check both SPO and OPS
- `?s p o` → PSO lookup
- `s p o` → Direct lookup in SPO

### 3. SPARQL Execution Model
1. **Tokenization** → 2. **Parsing** → 3. **Execution**

**Execution flow:**
```julia
execute_graph_patterns(store, patterns)
  ├─ execute_single_pattern(store, pattern, current_solutions)
  │   ├─ TriplePattern → execute_triple_pattern (use indexes)
  │   ├─ FilterPattern → execute_filter (evaluate expressions)
  │   ├─ OptionalPattern → execute_optional (left outer join)
  │   └─ UnionPattern → execute_union (alternatives)
  └─ Join results with existing solutions
```

### 4. SHACL Validation Model
1. **Target selection** (TargetClass, TargetNode, etc.)
2. **Shape application** (NodeShape, PropertyShape)
3. **Constraint checking** (MinCount, Datatype, Pattern, etc.)
4. **Report generation** (ValidationReport with ValidationResults)

## Key Components

### RDF Types (src/rdf/types.jl)

**Core types:**
```julia
abstract type RDFNode end
abstract type RDFTerm <: RDFNode end

struct IRI <: RDFTerm
    value::String
end

struct Literal <: RDFTerm
    value::String
    datatype::Union{IRI, Nothing}
    language::Union{String, Nothing}
end

struct BlankNode <: RDFNode
    id::String
end

struct Triple
    subject::Union{IRI, BlankNode}
    predicate::IRI
    object::RDFNode
end
```

**Important:** Literal constructors are defined OUTSIDE the struct to avoid method overwriting during precompilation.

### RDF Store (src/rdf/store.jl)

**Core operations:**
- `add!(store, s, p, o)` or `add!(store, triple)` - Adds to all three indexes
- `remove!(store, triple)` - Removes from all three indexes
- `triples(store; subject=nothing, predicate=nothing, object=nothing)` - Efficient lookup using appropriate index

**Optimization:**
- Use `triples(store, subject=x)` when possible (uses SPO index)
- Predicate-first queries use PSO index
- Object-first queries use OPS index

### SPARQL Executor (src/sparql/executor.jl)

**Query execution:**
- **Pattern matching**: Variables (Symbols) vs. concrete values (RDFNodes)
- **Variable binding**: Dict{Symbol, RDFNode}
- **Join strategy**: Nested loop joins with early filtering
- **FILTER evaluation**: Recursive expression evaluation

**Extension points:**
- Add new FilterExpression types in types.jl
- Implement evaluation in `evaluate_filter()`
- Add new GraphPattern types for advanced features

### SPARQL Parser (src/sparql/parser.jl)

**Hand-coded recursive descent parser:**
```julia
tokenize(query_string) → Vector{Token}
  ↓
parse_sparql(tokens) → SPARQLQuery
  ├─ parse_select()
  ├─ parse_construct()
  ├─ parse_ask()
  └─ parse_describe()
```

**Adding new syntax:**
1. Add token recognition in `tokenize()`
2. Add parsing logic in appropriate `parse_*()` function
3. Update grammar in types.jl if needed

### SHACL Validator (src/shacl/validator.jl)

**Constraint validation:**
Each constraint type has its own validation function:
```julia
validate_min_count(focus_node, path, constraint, shape, values)
validate_datatype(focus_node, path, constraint, shape, values)
validate_pattern(focus_node, path, constraint, shape, values)
# ... etc
```

**Adding new constraints:**
1. Define constraint type in types.jl
2. Add validation function in validator.jl
3. Register in `validate_constraint()` dispatch
4. Add tests in test/shacl/test_validator.jl

## Test Status and Known Issues

### Overall: 498/498 tests passing (100%) ✅

**All test phases passing:**
- ✅ RDF Foundation: 168/168 tests
- ✅ RDF Serialization: 75/75 tests (previously problematic, now fixed!)
- ✅ SPARQL: 180/180 tests (parser + executor)
- ✅ SHACL: 51/51 tests
- ✅ JSON-LD: 97/97 tests (integration + mapping)

All functionality tested and working perfectly, including previously problematic areas like language-tagged literal serialization and blank node handling.

## Previously Resolved Issues

Early development encountered serialization challenges with:
- Language-tagged literals (`"Hello"@en`)
- Blank node identity preservation

These have been fully resolved. See `TEST_FAILURES.md` for historical context.

### What Works Perfectly

- ✅ **All RDF operations** (add, remove, query)
- ✅ **All SPARQL features** (SELECT, CONSTRUCT, ASK, DESCRIBE, FILTER, OPTIONAL, UNION)
- ✅ **All SHACL validation** (all constraint types, all targets)
- ✅ **All RDF serialization** (Turtle, N-Triples, with language tags and blank nodes)
- ✅ **All JSON-LD features** (parsing, expansion, struct mapping, RDF integration)

## Working with the Codebase

### Adding a New SPARQL Feature

Example: Adding SPARQL 1.1 BIND

1. **Add to types** (`src/sparql/types.jl`):
```julia
struct BindPattern <: GraphPattern
    variable::Symbol
    expression::FilterExpression
end
```

2. **Add parser support** (`src/sparql/parser.jl`):
```julia
function parse_bind_pattern(state::ParserState)::BindPattern
    expect(state, :keyword, "BIND")
    expect(state, :symbol, "(")
    expr = parse_filter_expression(state)
    expect(state, :keyword, "AS")
    var_token = expect(state, :variable)
    expect(state, :symbol, ")")
    return BindPattern(Symbol(var_token.value[2:end]), expr)
end
```

3. **Add executor support** (`src/sparql/executor.jl`):
```julia
function execute_single_pattern(store::RDFStore, pattern::BindPattern,
                                solutions::Vector{Dict{Symbol, RDFNode}})
    new_solutions = Dict{Symbol, RDFNode}[]
    for solution in solutions
        value = evaluate_filter_expression(pattern.expression, solution)
        new_solution = copy(solution)
        new_solution[pattern.variable] = value
        push!(new_solutions, new_solution)
    end
    return new_solutions
end
```

4. **Add tests** (`test/sparql/test_executor.jl`):
```julia
@testset "BIND Pattern" begin
    store = RDFStore()
    # ... setup ...

    query_str = """
    SELECT ?x ?y
    WHERE {
        ?x <http://example.org/value> ?val .
        BIND(?val + 10 AS ?y)
    }
    """

    result = query(store, parse_sparql(query_str))
    @test length(result) > 0
end
```

### Adding a New SHACL Constraint

Example: Adding `sh:uniqueLang`

1. **Already defined in types** (`src/shacl/types.jl`):
```julia
struct UniqueLang <: Constraint
    unique_lang::Bool
end
```

2. **Add validator** (`src/shacl/validator.jl`):
```julia
function validate_unique_lang(focus_node::RDFNode, path::Union{IRI, Nothing},
                              constraint::UniqueLang, shape::Shape,
                              values::Vector{RDFNode})::Vector{ValidationResult}
    if !constraint.unique_lang
        return ValidationResult[]
    end

    # Check that language tags are unique
    langs = Set{Union{String, Nothing}}()
    for value in values
        if value isa Literal && !isnothing(value.language)
            if value.language in langs
                message = "Duplicate language tag: $(value.language)"
                return [ValidationResult(focus_node, constraint, shape,
                                       result_path=path, value=value,
                                       message=message)]
            end
            push!(langs, value.language)
        end
    end

    return ValidationResult[]
end

# Add to validate_constraint dispatch
elseif constraint isa UniqueLang
    return validate_unique_lang(focus_node, path, constraint, shape, values)
```

3. **Add tests** (`test/shacl/test_validator.jl`).

### Performance Optimization Tips

1. **Use specific triple patterns** in queries
   - `triples(store, subject=s)` is faster than filtering all triples

2. **Index statistics** are available
   - `count_subjects(store)`, `count_predicates(store)`, etc.
   - Use for query planning

3. **Avoid redundant queries**
   - Cache results when executing multiple queries
   - Use SPARQL's UNION instead of separate queries

4. **Consider query ordering**
   - Put most selective patterns first
   - Use FILTER after pattern matching when possible

## Common Pitfalls

### 1. Abstract Type Ordering
**Issue:** Using types before they're defined
```julia
# ❌ Wrong:
struct NodeShape <: Shape
    property_shapes::Vector{PropertyShape}  # PropertyShape not yet defined!
end

struct PropertyShape <: Shape
    # ...
end

# ✅ Correct: Define PropertyShape first
struct PropertyShape <: Shape
    # ...
end

struct NodeShape <: Shape
    property_shapes::Vector{PropertyShape}  # Now it exists
end
```

### 2. Literal Constructor Overloading
**Issue:** Method overwriting during precompilation
```julia
# ❌ Wrong:
struct Literal <: RDFTerm
    value::String

    Literal(value) = new(value, nothing, nothing)
    Literal(value, dt) = new(value, dt, nothing)  # Method overwrite!
end

# ✅ Correct: Define outside struct
struct Literal <: RDFTerm
    value::String
    datatype::Union{IRI, Nothing}
    language::Union{String, Nothing}

    # Only inner constructor
    function Literal(value, dt, lang)
        new(value, dt, lang)
    end
end

# Outer constructors (after struct definition)
Literal(value) = Literal(value, nothing, nothing)
Literal(value, dt::IRI) = Literal(value, dt, nothing)
```

### 3. Variable Naming
**Important:** SPARQL variables are represented as Julia `Symbol`s
```julia
# Query: SELECT ?person WHERE { ?person ?p ?o }
# In code:
:person  # Symbol for SPARQL variable ?person

# NOT:
"?person"  # ❌ String
"person"   # ❌ String without ?
```

### 4. Filter Evaluation Context
When implementing new filter functions, remember:
- Filters operate on variable bindings
- Must handle unbound variables gracefully
- Return `false` for incompatible types

## Testing Strategy

### Test Organization
```julia
@testset "Feature" begin
    @testset "Specific Case" begin
        # Setup
        store = RDFStore()
        # ... add data ...

        # Execute
        result = query(store, ...)

        # Assert
        @test condition
    end
end
```

### Running Tests
```bash
# All tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Specific test file
julia --project=. test/sparql/test_executor.jl

# With coverage
julia --project=. --code-coverage=user -e 'using Pkg; Pkg.test()'
```

### Writing Good Tests
1. **Test one thing** per @testset
2. **Use descriptive names** ("SELECT with FILTER" not "test1")
3. **Test edge cases** (empty results, missing values, etc.)
4. **Test error conditions** with @test_throws
5. **Keep tests independent** (don't rely on order)

## Dependencies

- **Serd.jl** (0.3.1): RDF serialization
  - Handles Turtle, N-Triples, N-Quads, TriG parsing
  - Known issue with language-tagged literal serialization
  - Active development: Check for updates

## Future Work

### High Priority
1. **Fix Serd.jl language tag serialization** (blocks 46 tests)
2. **SPARQL aggregations** (COUNT, SUM, AVG, MIN, MAX)
3. **SPARQL GROUP BY and HAVING**
4. **Query optimization** (join reordering, selectivity estimation)

### Medium Priority
1. **SPARQL property paths** (for complex graph navigation)
2. **SHACL-SPARQL** (SPARQL-based constraints)
3. **SHACL shape parsing** (read shapes from RDF)
4. **Performance benchmarking**

### Low Priority
1. **SPARQL 1.1 UPDATE** (INSERT, DELETE)
2. **RDF* / SPARQL*** (quoted triples)
3. **Named graphs** (GRAPH keyword)
4. **RDFS/OWL reasoning**
5. **Persistent storage** (disk-based store)

## Useful Commands

```bash
# Start Julia REPL with project
julia --project=.

# Precompile package
julia --project=. -e 'using LinkedData'

# Run tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Update dependencies
julia --project=. -e 'using Pkg; Pkg.update()'

# Check Serd.jl version
julia --project=. -e 'using Pkg; Pkg.status("Serd")'
```

## Questions to Ask

When extending the library:
1. **Does this fit the Julia idiom?** (dispatch, iterators, conventions)
2. **Will this break existing code?** (check API compatibility)
3. **Is this RDF-compliant?** (check W3C specifications)
4. **Is this SPARQL 1.1 compliant?** (check W3C SPARQL spec)
5. **Is this SHACL compliant?** (check W3C SHACL spec)
6. **Do we have tests?** (aim for >90% coverage)

## Resources

- [RDF 1.1 Specification](https://www.w3.org/TR/rdf11-concepts/)
- [SPARQL 1.1 Query Language](https://www.w3.org/TR/sparql11-query/)
- [SHACL Specification](https://www.w3.org/TR/shacl/)
- [Serd.jl Documentation](https://github.com/JuliaIO/Serd.jl)
- [Julia Documentation](https://docs.julialang.org/)

---

**Last updated:** 2026-02-09
**Library version:** 0.1.0
**Test pass rate:** 100% (498/498 tests)
