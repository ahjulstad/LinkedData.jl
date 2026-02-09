# RDF Serialization using Serd.jl
# Supports Turtle, N-Triples, N-Quads, and TriG formats

using Serd

"""
    parse_string!(store::RDFStore, content::String; format::Symbol=:turtle, base::Union{String, Nothing}=nothing) -> RDFStore

Parse RDF content from a string and add triples to the store.
Supported formats: :turtle, :ttl, :ntriples, :nt, :nquads, :nq, :trig
"""
function parse_string!(store::RDFStore, content::String;
                      format::Symbol=:turtle,
                      base::Union{String, Nothing}=nothing)::RDFStore

    syntax = _format_to_syntax(format)

    # Parse using Serd
    try
        statements = Serd.read_rdf_string(content, syntax=syntax)

        # First pass: collect namespace prefixes
        prefix_map = Dict{String, String}()
        for stmt in statements
            if stmt isa Serd.RDF.Prefix
                prefix_map[stmt.name] = stmt.uri
                register_namespace!(store, stmt.name, IRI(stmt.uri))
            end
        end

        # Second pass: process triples
        for stmt in statements
            if stmt isa Serd.RDF.Triple
                triple = _serd_to_triple(stmt, prefix_map)
                if !isnothing(triple)
                    add!(store, triple)
                end
            end
        end
    catch e
        throw(ErrorException("Failed to parse RDF: $(e)"))
    end

    return store
end

"""
    load!(store::RDFStore, filepath::String; format::Symbol=:auto, base::Union{String, Nothing}=nothing) -> RDFStore

Load RDF triples from a file into the store.
If format is :auto, it will be inferred from the file extension.
"""
function load!(store::RDFStore, filepath::String;
              format::Symbol=:auto,
              base::Union{String, Nothing}=nothing)::RDFStore

    if !isfile(filepath)
        throw(ArgumentError("File not found: $filepath"))
    end

    # Auto-detect format from extension
    if format == :auto
        format = _detect_format(filepath)
    end

    syntax = _format_to_syntax(format)

    # Parse using Serd
    try
        statements = Serd.read_rdf_file(filepath, syntax=syntax)

        # First pass: collect namespace prefixes
        prefix_map = Dict{String, String}()
        for stmt in statements
            if stmt isa Serd.RDF.Prefix
                prefix_map[stmt.name] = stmt.uri
                register_namespace!(store, stmt.name, IRI(stmt.uri))
            end
        end

        # Second pass: process triples
        for stmt in statements
            if stmt isa Serd.RDF.Triple
                triple = _serd_to_triple(stmt, prefix_map)
                if !isnothing(triple)
                    add!(store, triple)
                end
            end
        end
    catch e
        throw(ErrorException("Failed to load RDF file: $(e)"))
    end

    return store
end

"""
    save(store::RDFStore, filepath::String; format::Symbol=:turtle, base::Union{String, Nothing}=nothing) -> Nothing

Save RDF triples from the store to a file.
Supported formats: :turtle, :ttl, :ntriples, :nt
"""
function save(store::RDFStore, filepath::String;
             format::Symbol=:turtle,
             base::Union{String, Nothing}=nothing)

    fmt = _format_to_syntax(format)

    open(filepath, "w") do io
        if fmt in ("turtle", "trig")
            _write_turtle(io, store)
        else
            _write_ntriples(io, store)
        end
    end

    return nothing
end

# ============================================================================
# Helper Functions
# ============================================================================

"""
Convert format symbol to Serd syntax string.
"""
function _format_to_syntax(format::Symbol)::String
    if format in [:turtle, :ttl]
        return "turtle"
    elseif format in [:ntriples, :nt]
        return "ntriples"
    elseif format in [:nquads, :nq]
        return "nquads"
    elseif format == :trig
        return "trig"
    else
        throw(ArgumentError("Unsupported format: $format. Supported: :turtle, :ntriples, :nquads, :trig"))
    end
end

"""
Detect RDF format from file extension.
"""
function _detect_format(filepath::String)::Symbol
    ext = lowercase(split(filepath, ".")[end])

    if ext in ["ttl", "turtle"]
        return :turtle
    elseif ext in ["nt", "ntriples"]
        return :ntriples
    elseif ext in ["nq", "nquads"]
        return :nquads
    elseif ext == "trig"
        return :trig
    else
        # Default to Turtle
        return :turtle
    end
end

"""
Convert a Serd triple to our Triple type.
"""
function _serd_to_triple(stmt::Serd.RDF.Triple, prefix_map::Dict{String, String})::Union{Triple, Nothing}
    try
        # Convert subject
        subject = _serd_resource_to_node(stmt.subject, prefix_map)
        if !(subject isa Union{IRI, BlankNode})
            @warn "Invalid subject type: $(typeof(subject))"
            return nothing
        end

        # Convert predicate
        predicate = _serd_resource_to_node(stmt.predicate, prefix_map)
        if !(predicate isa IRI)
            @warn "Invalid predicate type: $(typeof(predicate))"
            return nothing
        end

        # Convert object (can be resource or literal)
        object = _serd_object_to_node(stmt.object, prefix_map)

        return Triple(subject, predicate, object)
    catch e
        @warn "Failed to convert Serd triple: $e"
        return nothing
    end
end

"""
Convert a Serd resource (subject/predicate) to our RDF node types.
"""
function _serd_resource_to_node(resource::Serd.RDF.Node, prefix_map::Dict{String, String})::Union{IRI, BlankNode}
    if resource isa Serd.RDF.ResourceURI
        return IRI(resource.uri)
    elseif resource isa Serd.RDF.ResourceCURIE
        # Expand CURIE to full IRI using prefix map
        if haskey(prefix_map, resource.prefix)
            full_uri = prefix_map[resource.prefix] * resource.name
            return IRI(full_uri)
        else
            throw(KeyError("Unknown prefix: $(resource.prefix)"))
        end
    elseif resource isa Serd.RDF.Blank
        return BlankNode("_:" * resource.name)
    else
        throw(ArgumentError("Unknown Serd resource type: $(typeof(resource))"))
    end
end

"""
Convert a Serd object (can be resource or literal) to our RDF node types.
"""
function _serd_object_to_node(obj::Serd.RDF.Node, prefix_map::Dict{String, String})::RDFNode
    if obj isa Serd.RDF.Literal
        # Serd.jl converts typed literals to native Julia types
        # We need to infer the datatype from the Julia type
        value_str = string(obj.value)

        # Check for language tag first
        if !isempty(obj.language)
            return Literal(value_str, lang=obj.language)
        end

        # Infer datatype from Julia type (Bool before Integer since Bool <: Integer)
        datatype = if obj.value isa Bool
            XSD.boolean
        elseif obj.value isa Integer
            XSD.integer
        elseif obj.value isa AbstractFloat
            XSD.double
        else
            nothing  # Plain string literal
        end

        if isnothing(datatype)
            return Literal(value_str)
        else
            return Literal(value_str, datatype)
        end
    else
        # It's a resource (IRI or blank node)
        return _serd_resource_to_node(obj, prefix_map)
    end
end

"""
Write store contents in N-Triples format.
"""
function _write_ntriples(io::IO, store::RDFStore)
    for triple in triples(store)
        print(io, _serialize_subject(triple.subject), " ")
        print(io, "<", triple.predicate.value, "> ")
        print(io, _serialize_object(triple.object))
        println(io, " .")
    end
end

"""
Write store contents in Turtle format.
"""
function _write_turtle(io::IO, store::RDFStore)
    # Write namespace prefixes
    for (name, iri) in store.namespaces
        println(io, "@prefix ", name, ": <", iri.value, "> .")
    end
    if !isempty(store.namespaces)
        println(io)
    end

    # Group triples by subject
    subjects = Dict{RDFNode, Vector{Triple}}()
    for triple in triples(store)
        push!(get!(subjects, triple.subject, Triple[]), triple)
    end

    first_subject = true
    for (subject, subject_triples) in subjects
        first_subject || println(io)
        first_subject = false

        print(io, _serialize_subject(subject))
        for (i, triple) in enumerate(subject_triples)
            if i == 1
                print(io, " ")
            else
                print(io, " ;\n    ")
            end
            print(io, "<", triple.predicate.value, "> ")
            print(io, _serialize_object(triple.object))
        end
        println(io, " .")
    end
end

"""Serialize an RDF subject node."""
function _serialize_subject(node::Union{IRI, BlankNode})::String
    if node isa IRI
        return "<$(node.value)>"
    else
        return node.id
    end
end

"""Serialize an RDF object node."""
function _serialize_object(node::RDFNode)::String
    if node isa IRI
        return "<$(node.value)>"
    elseif node isa BlankNode
        return node.id
    elseif node isa Literal
        escaped = replace(node.value, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\r" => "\\r")
        if !isnothing(node.datatype)
            return "\"$(escaped)\"^^<$(node.datatype.value)>"
        elseif !isnothing(node.language)
            return "\"$(escaped)\"@$(node.language)"
        else
            return "\"$(escaped)\""
        end
    else
        throw(ArgumentError("Unknown node type: $(typeof(node))"))
    end
end
