# Core RDF types following the RDF 1.1 specification

# Abstract types for RDF node hierarchy
abstract type RDFNode end
abstract type RDFTerm <: RDFNode end

# ============================================================================
# IRI - Internationalized Resource Identifier
# ============================================================================

struct IRI <: RDFTerm
    value::String

    function IRI(s::AbstractString)
        # Basic validation - IRIs should not contain spaces
        if occursin(r"\s", s)
            throw(ArgumentError("IRI cannot contain whitespace: $(s)"))
        end
        new(String(s))
    end
end

# Convenience constructor for string literals
Base.convert(::Type{IRI}, s::String) = IRI(s)

# Display methods
Base.show(io::IO, iri::IRI) = print(io, "<$(iri.value)>")
Base.string(iri::IRI) = iri.value

# Equality and hashing
Base.:(==)(a::IRI, b::IRI) = a.value == b.value
Base.hash(iri::IRI, h::UInt) = hash(iri.value, hash(:IRI, h))

# ============================================================================
# Literal - String values with optional datatype and language tags
# ============================================================================

struct Literal <: RDFTerm
    value::String
    datatype::Union{IRI, Nothing}
    language::Union{String, Nothing}

    function Literal(value::AbstractString, datatype::Union{IRI, Nothing}, language::Union{String, Nothing})
        # Validation: cannot have both datatype and language tag
        if !isnothing(datatype) && !isnothing(language)
            throw(ArgumentError("Literal cannot have both datatype and language tag"))
        end

        # Normalize language tag to lowercase
        lang = isnothing(language) ? nothing : lowercase(String(language))

        new(String(value), datatype, lang)
    end
end

# Convenience constructors (outside the struct)
# Typed literal with IRI datatype
Literal(value::AbstractString, datatype::IRI) = Literal(value, datatype, nothing)
# Typed literal with string datatype
Literal(value::AbstractString, datatype::AbstractString) = Literal(value, IRI(datatype), nothing)
# Language-tagged or plain literal (using keyword argument)
function Literal(value::AbstractString; lang::Union{String, Nothing}=nothing)
    Literal(value, nothing, lang)
end

# Display methods
function Base.show(io::IO, lit::Literal)
    print(io, "\"", escape_string(lit.value), "\"")
    if !isnothing(lit.language)
        print(io, "@", lit.language)
    elseif !isnothing(lit.datatype)
        print(io, "^^", lit.datatype)
    end
end

# Equality and hashing
function Base.:(==)(a::Literal, b::Literal)
    a.value == b.value && a.datatype == b.datatype && a.language == b.language
end

function Base.hash(lit::Literal, h::UInt)
    hash(lit.language, hash(lit.datatype, hash(lit.value, hash(:Literal, h))))
end

# ============================================================================
# BlankNode - Anonymous nodes
# ============================================================================

struct BlankNode <: RDFTerm
    id::String

    function BlankNode(id::AbstractString)
        new(String(id))
    end

    function BlankNode()
        # Generate unique ID using a random number
        new("_:b" * string(rand(UInt64), base=16))
    end
end

# Display methods
Base.show(io::IO, bn::BlankNode) = print(io, bn.id)
Base.string(bn::BlankNode) = bn.id

# Equality and hashing
Base.:(==)(a::BlankNode, b::BlankNode) = a.id == b.id
Base.hash(bn::BlankNode, h::UInt) = hash(bn.id, hash(:BlankNode, h))

# ============================================================================
# Triple - Subject-Predicate-Object statement
# ============================================================================

struct Triple
    subject::Union{IRI, BlankNode}
    predicate::IRI
    object::RDFNode

    function Triple(subject::Union{IRI, BlankNode}, predicate::IRI, object::RDFNode)
        new(subject, predicate, object)
    end
end

# Display methods
function Base.show(io::IO, triple::Triple)
    print(io, triple.subject, " ", triple.predicate, " ", triple.object, " .")
end

# Equality and hashing
function Base.:(==)(a::Triple, b::Triple)
    a.subject == b.subject && a.predicate == b.predicate && a.object == b.object
end

function Base.hash(triple::Triple, h::UInt)
    hash(triple.object, hash(triple.predicate, hash(triple.subject, hash(:Triple, h))))
end

# ============================================================================
# Quad - Triple with named graph context
# ============================================================================

struct Quad
    subject::Union{IRI, BlankNode}
    predicate::IRI
    object::RDFNode
    graph::Union{IRI, Nothing}

    function Quad(subject::Union{IRI, BlankNode}, predicate::IRI, object::RDFNode, graph::Union{IRI, Nothing}=nothing)
        new(subject, predicate, object, graph)
    end
end

# Convert Triple to Quad
Quad(triple::Triple, graph::Union{IRI, Nothing}=nothing) = Quad(triple.subject, triple.predicate, triple.object, graph)

# Display methods
function Base.show(io::IO, quad::Quad)
    print(io, quad.subject, " ", quad.predicate, " ", quad.object)
    if !isnothing(quad.graph)
        print(io, " ", quad.graph)
    end
    print(io, " .")
end

# Equality and hashing
function Base.:(==)(a::Quad, b::Quad)
    a.subject == b.subject && a.predicate == b.predicate && a.object == b.object && a.graph == b.graph
end

function Base.hash(quad::Quad, h::UInt)
    hash(quad.graph, hash(quad.object, hash(quad.predicate, hash(quad.subject, hash(:Quad, h)))))
end
