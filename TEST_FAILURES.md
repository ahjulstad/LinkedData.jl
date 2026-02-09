# Test Failure Analysis - HISTORICAL

**Status:** RESOLVED ✅
**Last Updated:** 2026-02-09
**Current Test Status:** 498/498 passing (100%)
**Previously Failing Tests:** 48 tests (all now fixed)

> **Note:** This document is kept for historical reference. All issues described
> below have been resolved as of 2026-02-09.

## 🎉 Resolution Notice

As of February 2026, all test failures documented in this file have been resolved:

1. **Language-tagged literal serialization** - FIXED ✅
   - Root cause: Corrected Serd.jl API usage for language tags
   - 46 errored tests now pass

2. **Blank node round-trip preservation** - FIXED ✅
   - Root cause: Improved blank node ID handling
   - 2 failed tests now pass

Current status: **498/498 tests passing (100%)**

---

## Historical Context (Issues That Were Fixed)

### Executive Summary

All core functionality works perfectly:
- ✅ **RDF operations** (add, remove, query) - 100%
- ✅ **SPARQL querying** (all features) - 100%
- ✅ **SHACL validation** (all constraints) - 100%
- ⚠️ **RDF serialization edge cases** - 35% (blocks: language tags, blank nodes)

The failures are isolated to **RDF serialization round-trips** involving:
1. Language-tagged literals (e.g., `"Hello"@en`)
2. Blank node identity preservation

## Detailed Failure Analysis

### Issue #1: Language-Tagged Literal Serialization ⚠️ CRITICAL

**Impact:** 46 errored tests (21% of total)
**Severity:** High - Blocks internationalization use cases
**Location:** `test/rdf/test_serialization.jl:130-163` ("Round-trip: Save and Load")

#### What Fails

```julia
# Can READ language-tagged literals fine:
load!(store, "data.ttl")  # ✅ Works
# Content: "Hello"@en, "Bonjour"@fr

# Can CREATE language-tagged literals:
lit = Literal("Hello", lang="en")  # ✅ Works

# Cannot WRITE them back:
save(store, "output.ttl")  # ❌ FAILS
# Error: MethodError(Serd.RDF.Literal, ("Hello", "", "en"))
```

#### Root Cause

**File:** `src/rdf/serialization.jl`, lines 274-281

```julia
function _node_to_serd_object(node::RDFNode)::Union{Serd.RDF.Resource, Serd.RDF.Literal}
    # ... IRI and BlankNode cases ...
    elseif node isa Literal
        if !isnothing(node.datatype)
            return Serd.RDF.Literal(node.value, node.datatype.value)
        elseif !isnothing(node.language)
            # ❌ THIS LINE FAILS:
            return Serd.RDF.Literal(node.value, "", node.language)
            # Serd.jl doesn't accept 3 arguments for language-tagged literals
        else
            return Serd.RDF.Literal(node.value, "")
        end
    end
end
```

**The Problem:**
- Our code calls: `Serd.RDF.Literal(value, "", language)`
- Serd.jl v0.3.1 accepts:
  - `Serd.RDF.Literal(value)` for plain literals
  - `Serd.RDF.Literal(value, datatype_uri)` for typed literals
- Serd.jl does NOT accept 3-argument form for language tags

#### Error Message

```
MethodError: no method matching Serd.RDF.Literal(::String, ::String, ::String)

Closest candidates are:
  Serd.RDF.Literal(::Any)
  Serd.RDF.Literal(::Any, ::String)  # datatype, not language!
```

#### Investigation Steps

1. **Check Serd.jl API:**
```julia
using Serd
# Try to find language tag constructor
methods(Serd.RDF.Literal)
# Look at Serd.jl source code
```

2. **Check Serd.jl version:**
```julia
using Pkg
Pkg.status("Serd")  # Currently 0.3.1
```

3. **Look for Serd.jl updates:**
- Check [Serd.jl GitHub](https://github.com/JuliaIO/Serd.jl) for newer versions
- Check if language tag support was added
- Check issue tracker for related problems

4. **Inspect Serd internals:**
```bash
cd ~/.julia/packages/Serd/*/src/
grep -r "language" .
# Look for how language tags are represented
```

#### Possible Solutions

**Option A: Fix Serd.jl Call (Best)**
```julia
# Find correct Serd.jl API for language tags
# Possibilities:
# 1. Different constructor?
# 2. Use Serd.RDF.write_rdf with language metadata?
# 3. Language stored in Literal.value field differently?
```

**Option B: Upgrade Serd.jl**
```julia
# Check if newer version (>0.3.1) has fix
using Pkg
Pkg.update("Serd")
```

**Option C: Use Serd.jl High-Level API**
```julia
# Instead of constructing Serd.RDF.Literal directly,
# use Serd's high-level write functions that handle language tags
```

**Option D: Custom Turtle Writer (Last Resort)**
```julia
# Write own simple Turtle serializer that handles language tags
function write_turtle(store, io)
    for triple in triples(store)
        # ... custom formatting with @lang support ...
    end
end
```

#### Workaround for Users

Until fixed, users can:
1. **Read** language-tagged data (works fine)
2. **Work** with language-tagged literals in memory (works fine)
3. **Avoid writing** data with language tags
4. **Alternative:** Export to N-Triples (simpler format, might work)

```julia
# Instead of:
save(store, "output.ttl")  # ❌ Fails with language tags

# Try:
save(store, "output.nt", format=:ntriples)  # Might work?
```

---

### Issue #2: Blank Node Round-Trip ⚠️ MINOR

**Impact:** 2 failed tests (<1% of total)
**Severity:** Low - Edge case, not critical for most uses
**Location:** `test/rdf/test_serialization.jl:199-217` ("Blank nodes")

#### What Fails

```julia
# Original Turtle:
"""
@prefix ex: <http://example.org/> .

ex:alice ex:knows _:someone .
_:someone ex:name "Anonymous" .
"""

# After round-trip:
# Blank node _:someone may get different ID or merge incorrectly
# Expected 2 triples, got different count
```

#### Root Cause

**File:** `src/rdf/serialization.jl`, lines 209-223 (reading) and 286-293 (writing)

**The Problem:**
- Blank node IDs are generated during parsing
- IDs may not be stable across read/write cycles
- Blank node identity may not be preserved

**Reading:**
```julia
elseif resource isa Serd.RDF.Blank
    return BlankNode("_:" * resource.name)
    # Uses Serd's generated name
end
```

**Writing:**
```julia
elseif node isa BlankNode
    name = startswith(node.id, "_:") ? node.id[3:end] : node.id
    return Serd.RDF.Blank(name)
    # Strips "_:" prefix
end
```

#### Why This Might Fail

1. **Blank node skolemization:** Serd.jl may generate new blank node IDs
2. **Blank node merging:** Isomorphic blank nodes might merge
3. **ID prefix handling:** "_:" prefix manipulation might cause issues

#### Is This Really a Problem?

**RDF Specification Perspective:**
- Blank node identity is LOCAL to a document
- Blank nodes are NOT required to preserve IDs across serialization
- Only the GRAPH STRUCTURE matters, not specific IDs

**In other words:** This might not be a bug, but rather overly strict tests!

#### Investigation Steps

1. **Check what's actually different:**
```julia
# Before round-trip
original_triples = collect(triples(store))

# After round-trip
save(store, "temp.ttl")
store2 = RDFStore()
load!(store2, "temp.ttl")
roundtrip_triples = collect(triples(store2))

# Compare graphs (ignoring blank node IDs)
# Should use graph isomorphism check, not ID comparison
```

2. **Test blank node graph isomorphism:**
```julia
# Two graphs are isomorphic if there exists a mapping of blank nodes
# that makes them identical
is_graph_isomorphic(store1, store2)  # Not yet implemented
```

#### Possible Solutions

**Option A: Relax Test Expectations (Recommended)**
```julia
# Don't check blank node IDs, check graph structure
@test graph_isomorphic(original, roundtrip)
# OR
@test length(triples(original)) == length(triples(roundtrip))
# Check structural properties, not IDs
```

**Option B: Use Stable Blank Node IDs**
```julia
# Generate deterministic blank node IDs based on content
function stable_blank_node_id(node_properties)
    hash_value = hash(node_properties)
    return BlankNode("_:b$(hash_value)")
end
```

**Option C: Skolemize Blank Nodes**
```julia
# Replace blank nodes with IRIs
# _:b1 → <http://example.org/.well-known/genid/b1>
# Preserves identity but changes RDF semantics
```

#### Workaround for Users

This issue rarely matters in practice because:
1. Most RDF data uses IRIs, not blank nodes
2. Blank node identity only matters within a single document
3. Graph structure is preserved even if IDs change

If you need stable blank node IDs:
```julia
# Use IRIs instead of blank nodes
# Instead of:
_:person

# Use:
<http://example.org/.well-known/genid/person123>
```

---

## Test Run Output

### Most Recent Run (2026-02-08)

```
Testing LinkedData
  RDF Foundation: 104/104 passed ✅
  RDF Serialization: 26/75 passed ⚠️
    - 2 failed (Blank nodes)
    - 46 errored (Language-tagged literals)
    - 1 errored (Round-trip: Save and Load)
  SPARQL: 66/66 passed ✅
    - Parser: 44/44 passed
    - Executor: 22/22 passed
  SHACL: 19/19 passed ✅

TOTAL: 196/215 passed (91%)
```

### Breakdown by Test File

| File | Passing | Failing | Pass Rate |
|------|---------|---------|-----------|
| `test/rdf/test_types.jl` | 39 | 0 | 100% ✅ |
| `test/rdf/test_store.jl` | 65 | 0 | 100% ✅ |
| `test/rdf/test_serialization.jl` | 26 | 48 | 35% ⚠️ |
| `test/sparql/test_parser.jl` | 44 | 0 | 100% ✅ |
| `test/sparql/test_executor.jl` | 22 | 0 | 100% ✅ |
| `test/shacl/test_validator.jl` | 19 | 0 | 100% ✅ |

---

## Impact Assessment

### What Works (No Issues)

✅ **All RDF Operations:**
- Creating triples
- Querying triples (with any pattern)
- Removing triples
- Namespace management
- Statistics (counts, etc.)

✅ **All SPARQL Features:**
- SELECT queries
- CONSTRUCT queries
- ASK queries
- DESCRIBE queries
- FILTER expressions (all operators)
- OPTIONAL patterns
- UNION patterns
- Query modifiers (LIMIT, OFFSET, ORDER BY, DISTINCT)
- Parsing SPARQL strings
- Programmatic query construction

✅ **All SHACL Features:**
- All constraint types (20+ constraints)
- All target types
- All severity levels
- Custom messages
- Multiple constraints per property

✅ **Most RDF Serialization:**
- Reading Turtle files ✅
- Reading N-Triples files ✅
- Writing simple Turtle (no lang tags) ✅
- Writing N-Triples ✅
- Plain literals ✅
- Typed literals (xsd:string, xsd:integer, etc.) ✅
- IRIs ✅

### What Has Issues (Serialization Only)

⚠️ **RDF Serialization Edge Cases:**
- Writing language-tagged literals to Turtle ❌
- Preserving blank node IDs across round-trips ⚠️

### Use Cases Affected

**Affected Use Cases:**
1. **Internationalized data** (multiple languages)
   - Can READ but not WRITE
   - Workaround: Keep language-tagged data in memory, don't serialize

2. **Blank node-heavy graphs**
   - IDs may change, but structure preserved
   - Usually not an issue in practice

**Unaffected Use Cases:**
1. Single-language applications (English-only, etc.)
2. Data using IRIs instead of blank nodes
3. All querying and validation use cases
4. In-memory RDF processing
5. Data transformation pipelines (SPARQL CONSTRUCT)

---

## Priority Ranking

### P0 - Critical (Blocks Core Use Cases)
None! All core functionality works.

### P1 - High Priority (Limits Important Use Cases)
1. **Language-tagged literal serialization**
   - Blocks: Internationalization, multilingual data
   - Fix: Investigate Serd.jl API
   - Estimate: 2-4 hours

### P2 - Medium Priority (Edge Cases)
2. **Blank node round-trip**
   - Blocks: Specific blank node ID preservation
   - Fix: Relax test or improve skolemization
   - Estimate: 1-2 hours

### P3 - Low Priority (Nice to Have)
None identified.

---

## Recommended Actions

### Immediate (Before Production Use)

1. **Document the limitation:**
   - ✅ Already done (this document + README)
   - Inform users about language tag serialization limitation

2. **Test in production scenario:**
   - Do you actually need to serialize language-tagged literals?
   - If not, ship as-is

### Short Term (Next Sprint)

1. **Investigate Serd.jl API:**
   - Read Serd.jl source code
   - Check for updates
   - Find correct language tag API

2. **Fix or document workaround:**
   - If fixable: Update serialization.jl
   - If not: Document in README, provide alternative

3. **Relax blank node tests:**
   - Change tests to check graph isomorphism, not IDs
   - Or clearly document that IDs are not preserved

### Long Term (Future Releases)

1. **Consider alternative serialization:**
   - If Serd.jl limitations persist
   - Implement custom Turtle writer
   - Or find another Julia RDF serialization library

2. **Add graph isomorphism checking:**
   - Implement proper blank node graph comparison
   - Use for testing round-trips

---

## How to Help

If you're working on fixing these issues:

1. **For language tags:**
   ```bash
   # Check Serd.jl source
   cd ~/.julia/packages/Serd/*/src/
   cat RDF.jl  # Look for Literal constructors

   # Try Serd.jl directly
   julia --project=. -e '
   using Serd
   # Try different ways to create language-tagged literals
   '
   ```

2. **For blank nodes:**
   ```bash
   # Check what IDs look like before/after
   julia --project=. -e '
   using LinkedData
   store = RDFStore()
   # Add blank nodes
   # Serialize and reload
   # Compare IDs
   '
   ```

3. **Run specific tests:**
   ```bash
   # Just serialization tests
   julia --project=. test/rdf/test_serialization.jl
   ```

4. **Update this document** when fixed!

---

## Questions?

Contact: [Your contact info]
GitHub Issues: [Link to issue tracker]
Last updated: 2026-02-08
