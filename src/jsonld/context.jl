# JSON-LD Context Processing

using JSON3

"""
    parse_context(json::String)::Context

Extract and parse the @context from a JSON-LD document string.

# Arguments
- `json::String` - JSON-LD document as string

# Returns
- `Context` - Parsed context object

# Example
```julia
json = \"\"\"{
  "@context": {"@vocab": "http://schema.org/"},
  "name": "Alice"
}\"\"\"
ctx = parse_context(json)
```
"""
function parse_context(json::String)::Context
    parsed = JSON3.read(json)

    if !haskey(parsed, "@context")
        return Context()  # Empty context
    end

    return parse_context_object(parsed["@context"])
end

"""
    parse_context_object(ctx_obj)::Context

Parse a @context value (can be string URL, dict, or array).

# Arguments
- `ctx_obj` - The @context value from JSON-LD (String, Dict, or Array)

# Returns
- `Context` - Parsed context object
"""
function parse_context_object(ctx_obj)::Context
    # Handle string context (URL reference)
    if ctx_obj isa String
        # For now, just treat as vocab
        # TODO: Fetch remote context in future
        return Context(vocab=IRI(ctx_obj))
    end

    # Handle array of contexts
    if ctx_obj isa Vector
        contexts = [parse_context_object(c) for c in ctx_obj]
        return merge_contexts(contexts...)
    end

    # Handle dict context
    base = nothing
    vocab = nothing
    prefixes = Dict{String, String}()
    terms = Dict{String, TermDefinition}()

    for (key, value) in pairs(ctx_obj)
        key_str = string(key)

        if key_str == "@base"
            base = IRI(string(value))
        elseif key_str == "@vocab"
            vocab = IRI(string(value))
        elseif startswith(key_str, "@")
            # Skip other keywords
            continue
        else
            # Term definition
            if value isa String
                # Simple string mapping
                value_str = string(value)
                if startswith(value_str, "@")
                    # Keyword alias
                    terms[key_str] = TermDefinition(value_str)
                else
                    # IRI mapping
                    terms[key_str] = TermDefinition(value_str)

                    # Check if it's a prefix (ends with : or / or #)
                    if endswith(value_str, ":") || endswith(value_str, "/") || endswith(value_str, "#")
                        prefixes[key_str] = value_str
                    end
                end
            elseif value isa Dict || haskey(value, "@id")
                # Expanded term definition
                term_iri = haskey(value, "@id") ? string(value["@id"]) : nothing
                type_mapping = haskey(value, "@type") ? string(value["@type"]) : nothing
                container = haskey(value, "@container") ? Symbol(value["@container"]) : nothing
                language = haskey(value, "@language") ? string(value["@language"]) : nothing
                reverse = haskey(value, "@reverse") ? value["@reverse"] : false

                terms[key_str] = TermDefinition(term_iri,
                                               type_mapping=type_mapping,
                                               container=container,
                                               language=language,
                                               reverse=reverse)

                # Add to prefixes if appropriate
                if !isnothing(term_iri) && (endswith(term_iri, ":") || endswith(term_iri, "/") || endswith(term_iri, "#"))
                    prefixes[key_str] = term_iri
                end
            end
        end
    end

    return Context(base, vocab, prefixes, terms)
end

"""
    merge_contexts(contexts::Context...)::Context

Merge multiple contexts, with later contexts overriding earlier ones.

# Arguments
- `contexts::Context...` - One or more contexts to merge

# Returns
- `Context` - Merged context

# Example
```julia
ctx1 = Context(vocab=IRI("http://schema.org/"))
ctx2 = Context(vocab=IRI("http://example.org/"))
merged = merge_contexts(ctx1, ctx2)  # ctx2 overrides
```
"""
function merge_contexts(contexts::Context...)::Context
    if length(contexts) == 0
        return Context()
    elseif length(contexts) == 1
        return contexts[1]
    end

    # Start with first context
    base = contexts[1].base
    vocab = contexts[1].vocab
    prefixes = copy(contexts[1].prefixes)
    terms = copy(contexts[1].terms)

    # Merge subsequent contexts (later ones override)
    for ctx in contexts[2:end]
        if !isnothing(ctx.base)
            base = ctx.base
        end
        if !isnothing(ctx.vocab)
            vocab = ctx.vocab
        end
        merge!(prefixes, ctx.prefixes)
        merge!(terms, ctx.terms)
    end

    return Context(base, vocab, prefixes, terms)
end

"""
    expand_iri(term::String, context::Context)::String

Expand a term or compact IRI to a full IRI using the context.

# Arguments
- `term::String` - The term or compact IRI to expand
- `context::Context` - The context to use for expansion

# Returns
- `String` - The expanded IRI

# Example
```julia
ctx = Context(vocab=IRI("http://schema.org/"))
expanded = expand_iri("name", ctx)  # "http://schema.org/name"
```
"""
function expand_iri(term::String, context::Context)::String
    # Already a full IRI
    if startswith(term, "http://") || startswith(term, "https://") || startswith(term, "urn:")
        return term
    end

    # Blank node
    if startswith(term, "_:")
        return term
    end

    # JSON-LD keyword
    if startswith(term, "@")
        return term
    end

    # Check for compact IRI (prefix:suffix)
    if occursin(":", term)
        parts = split(term, ":", limit=2)
        prefix = parts[1]
        suffix = length(parts) > 1 ? parts[2] : ""

        if haskey(context.prefixes, prefix)
            return context.prefixes[prefix] * suffix
        end
    end

    # Check term definitions
    if haskey(context.terms, term)
        term_def = context.terms[term]
        if !isnothing(term_def.iri)
            return term_def.iri
        end
    end

    # Apply vocabulary
    if !isnothing(context.vocab)
        return context.vocab.value * term
    end

    # Return as-is (relative IRI)
    return term
end

"""
    compact_iri(iri::String, context::Context)::String

Compact a full IRI to a term or prefix notation using the context.

# Arguments
- `iri::String` - The full IRI to compact
- `context::Context` - The context to use for compaction

# Returns
- `String` - The compacted term or IRI

# Example
```julia
ctx = Context(vocab=IRI("http://schema.org/"))
compacted = compact_iri("http://schema.org/name", ctx)  # "name"
```
"""
function compact_iri(iri::String, context::Context)::String
    # JSON-LD keywords pass through
    if startswith(iri, "@")
        return iri
    end

    # Blank nodes pass through
    if startswith(iri, "_:")
        return iri
    end

    # Try to find exact term match
    for (term, term_def) in context.terms
        if term_def.iri == iri
            return term
        end
    end

    # Try vocabulary compaction
    if !isnothing(context.vocab) && startswith(iri, context.vocab.value)
        suffix = replace(iri, context.vocab.value => "")
        # Only compact if suffix doesn't contain : or / (would be ambiguous)
        if !occursin(":", suffix) && !occursin("/", suffix)
            return suffix
        end
    end

    # Try prefix compaction (find longest matching prefix)
    best_prefix = nothing
    best_namespace = ""

    for (prefix, namespace) in context.prefixes
        if startswith(iri, namespace) && length(namespace) > length(best_namespace)
            best_prefix = prefix
            best_namespace = namespace
        end
    end

    if !isnothing(best_prefix)
        suffix = replace(iri, best_namespace => "")
        return "$(best_prefix):$(suffix)"
    end

    # Return full IRI
    return iri
end

"""
    context_to_dict(context::Context)::Dict

Convert a Context to a dictionary suitable for JSON-LD @context.

# Arguments
- `context::Context` - The context to convert

# Returns
- `Dict` - Dictionary representation of the context
"""
function context_to_dict(context::Context)::Dict{String, Any}
    result = Dict{String, Any}()

    if !isnothing(context.base)
        result["@base"] = context.base.value
    end

    if !isnothing(context.vocab)
        result["@vocab"] = context.vocab.value
    end

    # Add term definitions
    for (term, term_def) in context.terms
        if !isnothing(term_def.iri) &&
           isnothing(term_def.type_mapping) &&
           isnothing(term_def.container) &&
           isnothing(term_def.language) &&
           !term_def.reverse
            # Simple string mapping
            result[term] = term_def.iri
        else
            # Expanded definition
            def_dict = Dict{String, Any}()

            if !isnothing(term_def.iri)
                def_dict["@id"] = term_def.iri
            end
            if !isnothing(term_def.type_mapping)
                def_dict["@type"] = term_def.type_mapping
            end
            if !isnothing(term_def.container)
                def_dict["@container"] = string(term_def.container)
            end
            if !isnothing(term_def.language)
                def_dict["@language"] = term_def.language
            end
            if term_def.reverse
                def_dict["@reverse"] = true
            end

            result[term] = def_dict
        end
    end

    return result
end
