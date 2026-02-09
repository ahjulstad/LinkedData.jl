# JSON-LD Type Definitions

"""
    TermDefinition

Represents a term definition in a JSON-LD context.

A term definition maps a short term to a full IRI and optionally specifies:
- Type mapping (@id, @vocab, or a datatype IRI)
- Container type (@set, @list, @language, @index)
- Language tag for string values
- Reverse property indicator

# Fields
- `iri::Union{String, Nothing}` - The IRI this term maps to
- `type_mapping::Union{String, Nothing}` - Type coercion (@id, @vocab, or datatype IRI)
- `container::Union{Symbol, Nothing}` - Container type (:set, :list, :language, :index)
- `language::Union{String, Nothing}` - Default language tag for this term
- `reverse::Bool` - Whether this is a reverse property
"""
struct TermDefinition
    iri::Union{String, Nothing}
    type_mapping::Union{String, Nothing}
    container::Union{Symbol, Nothing}
    language::Union{String, Nothing}
    reverse::Bool

    function TermDefinition(iri::Union{String, Nothing};
                           type_mapping::Union{String, Nothing}=nothing,
                           container::Union{Symbol, Nothing}=nothing,
                           language::Union{String, Nothing}=nothing,
                           reverse::Bool=false)
        new(iri, type_mapping, container, language, reverse)
    end
end

# Convenience constructor for simple IRI mapping
TermDefinition(iri::String) = TermDefinition(iri, type_mapping=nothing, container=nothing,
                                             language=nothing, reverse=false)

"""
    Context

Represents a JSON-LD @context for expanding and compacting IRIs.

A context defines namespace mappings, vocabulary, and term definitions that
control how JSON-LD documents are processed.

# Fields
- `base::Union{IRI, Nothing}` - Base IRI for resolving relative IRIs (@base)
- `vocab::Union{IRI, Nothing}` - Default vocabulary for unmapped terms (@vocab)
- `prefixes::Dict{String, String}` - Namespace prefix mappings (e.g., "schema" => "http://schema.org/")
- `terms::Dict{String, TermDefinition}` - Term definitions for property mappings
"""
struct Context
    base::Union{IRI, Nothing}
    vocab::Union{IRI, Nothing}
    prefixes::Dict{String, String}
    terms::Dict{String, TermDefinition}

    # Inner constructor requires all fields
    function Context(base::Union{IRI, Nothing},
                    vocab::Union{IRI, Nothing},
                    prefixes::Dict{String, String},
                    terms::Dict{String, TermDefinition})
        new(base, vocab, prefixes, terms)
    end
end

# Outer convenience constructors (after struct definition)
# Keyword constructor handles Context() case with defaults
Context(; base::Union{IRI, Nothing}=nothing, vocab::Union{IRI, Nothing}=nothing) =
    Context(base, vocab, Dict{String, String}(), Dict{String, TermDefinition}())

"""
    ConversionOptions

Options for controlling JSON-LD conversion behavior.

# Fields
- `compact::Bool` - Whether to output compacted JSON-LD (true) or expanded (false)
- `context::Union{Context, String, Nothing}` - Context to use for compaction/expansion
- `generate_blank_nodes::Bool` - Whether to auto-generate blank node IDs
- `validate::Bool` - Whether to run SHACL validation after conversion
"""
struct ConversionOptions
    compact::Bool
    context::Union{Context, String, Nothing}
    generate_blank_nodes::Bool
    validate::Bool

    # Inner constructor requires all fields
    function ConversionOptions(compact::Bool,
                               context::Union{Context, String, Nothing},
                               generate_blank_nodes::Bool,
                               validate::Bool)
        new(compact, context, generate_blank_nodes, validate)
    end
end

# Outer convenience constructors (after struct definition)
# Keyword constructor handles ConversionOptions() case with defaults
ConversionOptions(; compact::Bool=true,
                   context::Union{Context, String, Nothing}=nothing,
                   generate_blank_nodes::Bool=true,
                   validate::Bool=false) =
    ConversionOptions(compact, context, generate_blank_nodes, validate)

"""
    TypeMapping

Metadata for mapping between Julia struct types and JSON-LD representations.

Stores information about how a Julia struct should be serialized to/from JSON-LD,
including field mappings, RDF type, and context.

# Fields
- `julia_type::Type` - The Julia struct type
- `rdf_type::IRI` - The RDF type IRI (maps to @type in JSON-LD)
- `context::Union{Context, String}` - Context for this type
- `field_mappings::Dict{Symbol, String}` - Maps Julia field names to JSON-LD properties
- `id_field::Union{Symbol, Nothing}` - Which field corresponds to @id (if any)
"""
struct TypeMapping
    julia_type::Type
    rdf_type::IRI
    context::Union{Context, String}
    field_mappings::Dict{Symbol, String}
    id_field::Union{Symbol, Nothing}

    # Inner constructor requires all fields
    function TypeMapping(julia_type::Type,
                        rdf_type::IRI,
                        context::Union{Context, String},
                        field_mappings::Dict{Symbol, String},
                        id_field::Union{Symbol, Nothing})
        new(julia_type, rdf_type, context, field_mappings, id_field)
    end
end

# Outer convenience constructors (after struct definition)
TypeMapping(julia_type::Type, rdf_type::IRI, context::Union{Context, String}) =
    TypeMapping(julia_type, rdf_type, context, Dict{Symbol, String}(), nothing)

"""
    JSONLDObject

A dynamic wrapper around parsed JSON-LD data that provides convenient access
to properties while preserving JSON-LD semantics.

Use this for exploratory parsing when you don't know the type in advance.
For optimized processing of many objects, use typed parsing with `from_jsonld(Type{T}, json)`.

# Fields
- `data::Dict{String, Any}` - The expanded JSON-LD data
- `context::Union{Context, Nothing}` - The context used during parsing

# Example
```julia
json = \"\"\"{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Person",
  "name": "Alice"
}\"\"\"

obj = from_jsonld(json)  # Returns JSONLDObject
obj.name  # "Alice"
obj.type  # "http://schema.org/Person"
```
"""
struct JSONLDObject
    data::Dict{String, Any}
    context::Union{Context, Nothing}

    function JSONLDObject(data::Dict{String, Any}, context::Union{Context, Nothing}=nothing)
        new(data, context)
    end
end

# Convenient property access
function Base.getproperty(obj::JSONLDObject, name::Symbol)
    if name == :data || name == :context
        return getfield(obj, name)
    end

    data = getfield(obj, :data)

    # Handle special JSON-LD properties
    if name == :id
        return get(data, "@id", nothing)
    elseif name == :type
        types = get(data, "@type", String[])
        return types isa Vector ? types : [types]
    end

    # Try to find property by name
    name_str = string(name)

    # Try direct access
    if haskey(data, name_str)
        return _unwrap_value(data[name_str])
    end

    # Try with context expansion
    ctx = getfield(obj, :context)
    if !isnothing(ctx)
        expanded = expand_iri(name_str, ctx)
        if haskey(data, expanded)
            return _unwrap_value(data[expanded])
        end
    end

    return nothing
end

# Helper to unwrap JSON-LD value objects
function _unwrap_value(val)
    if val isa Vector
        # Unwrap each element
        unwrapped = [_unwrap_single_value(v) for v in val]
        # If single-element array, return the element directly
        # (JSON-LD expanded form uses arrays for all properties,
        # but for convenience we unwrap single values)
        return length(unwrapped) == 1 ? unwrapped[1] : unwrapped
    else
        return _unwrap_single_value(val)
    end
end

function _unwrap_single_value(val)
    if val isa Dict
        if haskey(val, "@value")
            return val["@value"]
        elseif haskey(val, "@id")
            return val["@id"]
        else
            # Nested object - wrap it
            return JSONLDObject(val, nothing)
        end
    end
    return val
end

# Display
function Base.show(io::IO, obj::JSONLDObject)
    types = obj.type
    id = obj.id

    print(io, "JSONLDObject(")
    if !isnothing(id)
        print(io, "@id=\"$id\"")
        if !isempty(types)
            print(io, ", ")
        end
    end
    if !isempty(types)
        print(io, "@type=", types)
    end
    print(io, ")")
end

# Global registry for type mappings (populated by @jsonld macro)
const TYPE_REGISTRY = Dict{Type, TypeMapping}()

# Extension point for future SHACL-generated types
const SHACL_GENERATED_TYPES = Dict{Type, TypeMapping}()
