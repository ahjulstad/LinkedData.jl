# JSON-LD Guide for LinkedData.jl

This guide covers the JSON-LD functionality in LinkedData.jl, showing how to work with semantic web data using idiomatic Julia structs.

## Table of Contents

- [Introduction](#introduction)
- [Quick Start](#quick-start)
- [Dynamic vs Typed Parsing](#dynamic-vs-typed-parsing)
- [Field Naming Conventions](#field-naming-conventions)
- [Working with Contexts](#working-with-contexts)
- [Customizing Mappings](#customizing-mappings)
- [Integration with RDF Store](#integration-with-rdf-store)
- [Performance Considerations](#performance-considerations)
- [Best Practices](#best-practices)
- [Examples](#examples)

## Introduction

JSON-LD (JSON for Linking Data) is a method for encoding Linked Data using JSON. LinkedData.jl provides seamless bidirectional conversion between JSON-LD documents and Julia structs, allowing you to:

- Work with semantic web data in a type-safe way
- Automatically map between Julia conventions and JSON-LD standards
- Integrate JSON-LD data with SPARQL queries and SHACL validation
- Process large amounts of JSON-LD data efficiently

## Quick Start

```julia
using LinkedData

# Parse JSON-LD without declaring a type
json = """
{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Person",
  "name": "Alice",
  "age": 30
}
"""

obj = from_jsonld(json)
println(obj.name)  # "Alice"
println(obj.age)   # 30
```

## Dynamic vs Typed Parsing

### Dynamic Parsing: JSONLDObject

Use when you don't know the structure in advance or are exploring data:

```julia
json = """
{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Article",
  "@id": "http://example.org/article1",
  "headline": "Breaking News",
  "datePublished": "2026-02-09",
  "author": {
    "@type": "Person",
    "name": "Jane Doe"
  }
}
"""

article = from_jsonld(json)

# Access properties dynamically
println(article.headline)        # "Breaking News"
println(article.datePublished)   # "2026-02-09"
println(article.id)              # "http://example.org/article1"
println(article.type)            # ["http://schema.org/Article"]

# Nested objects are also JSONLDObjects
println(article.author.name)     # "Jane Doe"
```

**Pros:**
- No type declaration needed
- Great for exploration and one-off parsing
- Handles any JSON-LD structure

**Cons:**
- No compile-time type checking
- Slower than typed parsing
- No IDE autocomplete

### Typed Parsing: Julia Structs

Use when you know the structure and want type safety and performance:

```julia
@jsonld struct Article
    id::Union{String, Nothing}
    headline::String
    date_published::Union{String, Nothing}  # Maps to "datePublished"
    author_name::Union{String, Nothing}     # Custom field
end

article = from_jsonld(Article, json)

# Compile-time type safety
println(article.headline)        # String
println(article.date_published)  # Union{String, Nothing}
```

**Pros:**
- Type-safe: compiler catches errors
- Fast: optimized conversion
- IDE autocomplete works
- Type mapping cached for repeated use

**Cons:**
- Requires struct definition
- Less flexible for varying structures

## Field Naming Conventions

LinkedData.jl automatically converts between Julia's `snake_case` and JSON-LD's `camelCase`:

```julia
@jsonld struct Employee
    id::Union{String, Nothing}
    first_name::String          # → "firstName"
    last_name::String           # → "lastName"
    employee_id::String         # → "employeeId"
    date_of_birth::String       # → "dateOfBirth"
end

json = """
{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Employee",
  "firstName": "Alice",
  "lastName": "Smith",
  "employeeId": "E12345",
  "dateOfBirth": "1990-01-01"
}
"""

employee = from_jsonld(Employee, json)
println(employee.first_name)    # "Alice"
println(employee.employee_id)   # "E12345"
```

### Special Fields

- `id` → `@id` (IRI of the node)
- `type` or `types` → `@type` (RDF type(s))

```julia
@jsonld struct Thing
    id::Union{String, Nothing}      # Maps to @id
    type::Union{String, Nothing}    # Maps to @type (single)
    name::String
end

# Or for multiple types:
@jsonld struct Thing
    id::Union{String, Nothing}
    types::Vector{String}           # Maps to @type (array)
    name::String
end
```

## Working with Contexts

### Using Built-in Contexts

```julia
json = """
{
  "@context": "http://schema.org/",
  "@type": "Person",
  "name": "Alice"
}
"""

obj = from_jsonld(json)
```

### Custom Vocabularies

```julia
json = """
{
  "@context": {
    "@vocab": "http://example.org/vocab/",
    "foaf": "http://xmlns.com/foaf/0.1/"
  },
  "@type": "Person",
  "name": "Alice",
  "foaf:knows": {
    "@id": "http://example.org/bob"
  }
}
"""

obj = from_jsonld(json)
```

### Prefix Notation

```julia
json = """
{
  "@context": {
    "schema": "http://schema.org/",
    "ex": "http://example.org/"
  },
  "@type": "schema:Person",
  "@id": "ex:alice",
  "schema:name": "Alice"
}
"""

obj = from_jsonld(json)
```

## Customizing Mappings

### Custom RDF Type

By default, struct names map to `http://schema.org/{StructName}`. Override this:

```julia
@jsonld struct Product
    id::Union{String, Nothing}
    name::String
    price::Float64
end

# Custom RDF type IRI
LinkedData.rdf_type(::Type{Product}) = IRI("http://example.org/Product")
```

### Custom Context

```julia
@jsonld struct Employee
    id::Union{String, Nothing}
    name::String
end

# Custom context
LinkedData.jsonld_context(::Type{Employee}) = Context(
    vocab=IRI("http://example.org/vocab/")
)
```

### Custom Field Mapping

Override automatic snake_case → camelCase conversion:

```julia
@jsonld struct Product
    id::Union{String, Nothing}
    name::String
    sku_code::String
end

# Map sku_code → "SKU" instead of "skuCode"
LinkedData.field_mapping(::Type{Product}, ::Val{:sku_code}) = "SKU"
```

## Integration with RDF Store

### JSON-LD to Triples

```julia
store = RDFStore()

json = """
{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Person",
  "@id": "http://example.org/alice",
  "name": "Alice",
  "email": "alice@example.org"
}
"""

# Parse and add to store
jsonld_to_triples!(store, json)

# Now query with SPARQL
result = query(store, parse_sparql("""
    SELECT ?name WHERE {
        <http://example.org/alice> <http://schema.org/name> ?name .
    }
"""))
```

### Triples to JSON-LD

```julia
# Given a store with triples
store = RDFStore()
alice = IRI("http://example.org/alice")
add!(store, alice, RDF.type_, IRI("http://schema.org/Person"))
add!(store, alice, IRI("http://schema.org/name"), Literal("Alice"))

# Serialize to JSON-LD
context = Context(vocab=IRI("http://schema.org/"))
json = triples_to_jsonld(store,
                        context=context,
                        subject=alice)

println(json)
# {
#   "@context": {"@vocab": "http://schema.org/"},
#   "@id": "http://example.org/alice",
#   "@type": "Person",
#   "name": "Alice"
# }
```

## Performance Considerations

### Use @jsonld for Repeated Parsing

If you're parsing many objects of the same type, use `@jsonld` to cache the type mapping:

```julia
@jsonld struct Person
    id::Union{String, Nothing}
    name::String
end

# Type mapping computed once and cached
for json in json_documents
    person = from_jsonld(Person, json)  # Fast: reuses cached mapping
    process(person)
end
```

Without `@jsonld`, the mapping is inferred every time, which is slower.

### Batch Processing

```julia
@jsonld struct Person
    id::Union{String, Nothing}
    name::String
    age::Union{Int, Nothing}
end

# Process a large dataset efficiently
people = Person[]
for json in large_json_dataset
    push!(people, from_jsonld(Person, json))
end

# Now work with typed data
adults = filter(p -> !isnothing(p.age) && p.age >= 18, people)
```

## Best Practices

### 1. Use Union{T, Nothing} for Optional Fields

```julia
@jsonld struct Person
    id::Union{String, Nothing}       # Optional
    name::String                     # Required
    email::Union{String, Nothing}    # Optional
    age::Union{Int, Nothing}         # Optional
end
```

### 2. Prefer snake_case Field Names

Let the library handle conversion to camelCase:

```julia
# Good
@jsonld struct Employee
    employee_id::String
    first_name::String
end

# Avoid (unless you have a specific reason)
@jsonld struct Employee
    employeeId::String
    firstName::String
end
```

### 3. Use @jsonld for Types You'll Parse Multiple Times

```julia
# If parsing many Person objects
@jsonld struct Person
    id::Union{String, Nothing}
    name::String
end

# If parsing once or exploring, skip @jsonld
struct ExperimentalType
    id::Union{String, Nothing}
    data::String
end
```

### 4. Handle Multiple Types Explicitly

```julia
json = """
{
  "@type": ["Person", "Employee"]
}
"""

# Use types field (plural) for multiple types
@jsonld struct PersonEmployee
    id::Union{String, Nothing}
    types::Vector{String}  # Will contain both types
end
```

### 5. Validate Before Parsing

Use SHACL to validate JSON-LD structure before parsing into typed structs:

```julia
# Parse and add to store
store = RDFStore()
jsonld_to_triples!(store, json)

# Validate structure
report = validate(store, [person_shape])

if report.conforms
    # Safe to parse into typed struct
    person = from_jsonld(Person, json)
else
    # Handle validation errors
    println("Invalid JSON-LD structure")
end
```

## Examples

### Example 1: Blog Post with Author

```julia
@jsonld struct BlogPost
    id::Union{String, Nothing}
    headline::String
    article_body::String
    date_published::Union{String, Nothing}
    author_name::Union{String, Nothing}
end

json = """
{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "BlogPost",
  "@id": "http://example.org/posts/1",
  "headline": "Introduction to Linked Data",
  "articleBody": "Linked Data is...",
  "datePublished": "2026-02-09",
  "authorName": "Alice Smith"
}
"""

post = from_jsonld(BlogPost, json)
println("$(post.headline) by $(post.author_name)")
```

### Example 2: Product Catalog

```julia
@jsonld struct Product
    id::Union{String, Nothing}
    name::String
    description::Union{String, Nothing}
    price::Union{Float64, Nothing}
    availability::Union{String, Nothing}
end

json = """
{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Product",
  "name": "Laptop",
  "description": "High-performance laptop",
  "price": 999.99,
  "availability": "InStock"
}
"""

product = from_jsonld(Product, json)

if !isnothing(product.price) && product.price < 1000
    println("$(product.name) is on sale!")
end
```

### Example 3: Scientific Dataset

```julia
@jsonld struct Dataset
    id::Union{String, Nothing}
    name::String
    description::Union{String, Nothing}
    creator_name::Union{String, Nothing}
    date_published::Union{String, Nothing}
    keywords::Vector{String}
end

json = """
{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Dataset",
  "@id": "http://example.org/datasets/climate-2026",
  "name": "Climate Data 2026",
  "description": "Comprehensive climate measurements",
  "creatorName": "Dr. Jane Smith",
  "datePublished": "2026-01-15",
  "keywords": ["climate", "temperature", "precipitation"]
}
"""

dataset = from_jsonld(Dataset, json)
println("Dataset: $(dataset.name)")
println("Keywords: $(join(dataset.keywords, ", "))")
```

### Example 4: Organization with Multiple Locations

```julia
@jsonld struct Organization
    id::Union{String, Nothing}
    name::String
    description::Union{String, Nothing}
    locations::Vector{String}
end

json = """
{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Organization",
  "@id": "http://example.org/acme-corp",
  "name": "ACME Corporation",
  "description": "Leading technology company",
  "locations": ["New York", "London", "Tokyo"]
}
"""

org = from_jsonld(Organization, json)
println("$(org.name) operates in $(length(org.locations)) cities")
```

### Example 5: Complete Workflow

```julia
using LinkedData

# 1. Define struct
@jsonld struct Person
    id::Union{String, Nothing}
    name::String
    email::Union{String, Nothing}
    age::Union{Int, Nothing}
end

# 2. Parse JSON-LD
json = """
{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Person",
  "@id": "http://example.org/alice",
  "name": "Alice",
  "email": "alice@example.org",
  "age": 30
}
"""

person = from_jsonld(Person, json)

# 3. Add to RDF store
store = RDFStore()
jsonld_to_triples!(store, json)

# 4. Query with SPARQL
result = query(store, parse_sparql("""
    SELECT ?name ?age WHERE {
        ?person a <http://schema.org/Person> ;
                <http://schema.org/name> ?name ;
                <http://schema.org/age> ?age .
        FILTER (?age > 25)
    }
"""))

for binding in result
    println("$(binding[:name].value) is $(binding[:age].value)")
end

# 5. Validate with SHACL
person_shape = NodeShape(
    IRI("http://example.org/PersonShape"),
    targets=[TargetClass(IRI("http://schema.org/Person"))],
    property_shapes=[
        PropertyShape(
            IRI("http://schema.org/name"),
            constraints=[MinCount(1), MaxCount(1)]
        ),
        PropertyShape(
            IRI("http://schema.org/age"),
            constraints=[Datatype(XSD.integer), MinInclusive(0), MaxInclusive(150)]
        )
    ]
)

report = validate(store, [person_shape])
println(report.conforms ? "✓ Valid" : "✗ Invalid")

# 6. Serialize back to JSON-LD
json_out = to_jsonld(person)
println(json_out)
```

## Troubleshooting

### Property Not Found

If a property isn't being parsed:

1. Check field name matches camelCase conversion
2. Verify the property exists in the JSON-LD
3. Check if it's being filtered by the context
4. Use dynamic parsing to explore: `obj = from_jsonld(json); println(obj.data)`

### Type Mismatch Errors

```julia
# Error: Expected Int, got String
@jsonld struct Person
    age::Int  # Won't accept null/missing
end

# Fix: Use Union{Int, Nothing}
@jsonld struct Person
    age::Union{Int, Nothing}
end
```

### Context Issues

If IRIs aren't expanding correctly:

```julia
# Debug expansion
json = """{"@context": {...}, ...}"""
expanded = expand(json)
println(expanded)  # See the fully expanded form
```

## Further Reading

- [JSON-LD 1.1 Specification](https://www.w3.org/TR/json-ld11/)
- [Schema.org Vocabulary](https://schema.org/)
- [JSON-LD Playground](https://json-ld.org/playground/)
- [LinkedData.jl README](../README.md)

---

**Questions or Issues?** Please open an issue on the GitHub repository.
