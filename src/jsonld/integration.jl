# JSON-LD RDFStore Integration

using JSON3

"""
    jsonld_to_triples!(store::RDFStore, json::String; base::Union{String, Nothing}=nothing)::RDFStore

Parse a JSON-LD document and add the resulting triples to the store.

This function follows the pattern of `parse_string!()` from serialization.jl.
It expands the JSON-LD document to normalize it, then converts each node to triples.

# Arguments
- `store::RDFStore` - The store to add triples to (modified in-place)
- `json::String` - JSON-LD document as string
- `base::Union{String, Nothing}` - Optional base IRI for resolving relative IRIs

# Returns
- `RDFStore` - The modified store (for chaining)

# Example
```julia
store = RDFStore()

json = \"\"\"{
  "@context": {"@vocab": "http://schema.org/"},
  "@id": "http://example.org/alice",
  "@type": "Person",
  "name": "Alice",
  "age": 30
}\"\"\"

jsonld_to_triples!(store, json)
println(length(store))  # 3 triples
```
"""
function jsonld_to_triples!(store::RDFStore, json::String;
                           base::Union{String, Nothing}=nothing)::RDFStore
    # Parse JSON
    parsed = JSON3.read(json)

    # Create context with base if provided
    base_context = isnothing(base) ? nothing : Context(base=IRI(base))

    # Expand JSON-LD
    expanded = expand(parsed, base_context)

    # Convert each expanded node to triples
    for node in expanded
        node_to_triples!(store, node)
    end

    return store
end

"""
    node_to_triples!(store::RDFStore, node::Dict)

Convert an expanded JSON-LD node to triples and add to store.

# Arguments
- `store::RDFStore` - The store to add triples to
- `node::Dict` - Expanded JSON-LD node object

# Returns
- Nothing (modifies store in-place)
"""
function node_to_triples!(store::RDFStore, node::Dict)
    # Get subject
    subject = get_subject_node(node)

    # Handle @type (rdf:type triples)
    if haskey(node, "@type")
        for type_iri in node["@type"]
            add!(store, subject, RDF.type_, IRI(type_iri))
        end
    end

    # Handle properties
    for (property_iri, values) in node
        # Skip keywords
        if property_iri in ["@id", "@type", "@context"]
            continue
        end

        # Skip other keywords
        if startswith(property_iri, "@")
            continue
        end

        predicate = IRI(property_iri)

        # Handle array of values
        values_array = values isa Vector ? values : [values]

        for value in values_array
            object_node = value_to_node(value)

            # Skip if couldn't convert
            if isnothing(object_node)
                continue
            end

            # Add triple
            add!(store, subject, predicate, object_node)
        end
    end
end

"""
    get_subject_node(node::Dict)::Union{IRI, BlankNode}

Extract the subject IRI or generate a blank node from an expanded JSON-LD node.

# Arguments
- `node::Dict` - Expanded JSON-LD node

# Returns
- `Union{IRI, BlankNode}` - The subject node
"""
function get_subject_node(node::Dict)::Union{IRI, BlankNode}
    if haskey(node, "@id")
        id = string(node["@id"])

        # Check if blank node
        if startswith(id, "_:")
            return BlankNode(replace(id, "_:" => ""))
        else
            return IRI(id)
        end
    else
        # Generate blank node
        return BlankNode()
    end
end

"""
    value_to_node(value)::Union{RDFNode, Nothing}

Convert an expanded JSON-LD value to an RDFNode (IRI, Literal, or BlankNode).

# Arguments
- `value` - Expanded JSON-LD value (can be Dict with @value/@id or nested node)

# Returns
- `Union{RDFNode, Nothing}` - The converted RDF node, or nothing if invalid
"""
function value_to_node(value)::Union{RDFNode, Nothing}
    # Null
    if isnothing(value)
        return nothing
    end

    # Dictionary (value object, ID reference, or nested node)
    if value isa Dict
        # @value object (literal)
        if haskey(value, "@value")
            val = value["@value"]
            val_str = string(val)

            # Language-tagged string
            if haskey(value, "@language")
                lang = string(value["@language"])
                return Literal(val_str, lang=lang)
            end

            # Typed literal
            if haskey(value, "@type")
                datatype_iri = string(value["@type"])
                return Literal(val_str, IRI(datatype_iri))
            end

            # Plain literal (but preserve Julia types in string representation)
            return Literal(val_str)
        end

        # @id reference
        if haskey(value, "@id")
            id = string(value["@id"])

            if startswith(id, "_:")
                return BlankNode(replace(id, "_:" => ""))
            else
                return IRI(id)
            end
        end

        # Nested node (would need recursion - for now, generate blank node)
        # This is a simplification; full implementation would recursively process
        return BlankNode()
    end

    # Plain scalar (shouldn't happen in expanded form, but handle gracefully)
    return Literal(string(value))
end

"""
    triples_to_jsonld(store::RDFStore;
                     context::Union{Context, Nothing}=nothing,
                     subject::Union{RDFNode, Nothing}=nothing)::String

Convert triples from the store to JSON-LD format.

# Arguments
- `store::RDFStore` - The store to query triples from
- `context::Union{Context, Nothing}` - Optional context for compaction
- `subject::Union{RDFNode, Nothing}` - Optional subject to filter by (single node)

# Returns
- `String` - JSON-LD document as string

# Example
```julia
store = RDFStore()
alice = IRI("http://example.org/alice")
add!(store, alice, RDF.type_, IRI("http://schema.org/Person"))
add!(store, alice, IRI("http://schema.org/name"), Literal("Alice"))

ctx = Context(vocab=IRI("http://schema.org/"))
json = triples_to_jsonld(store, context=ctx, subject=alice)
```
"""
function triples_to_jsonld(store::RDFStore;
                          context::Union{Context, Nothing}=nothing,
                          subject::Union{RDFNode, Nothing}=nothing)::String
    # Query triples
    triple_list = if isnothing(subject)
        collect(store)
    else
        collect(triples(store, subject=subject))
    end

    # Group by subject
    subjects_map = Dict{RDFNode, Vector{Triple}}()
    for triple in triple_list
        if !haskey(subjects_map, triple.subject)
            subjects_map[triple.subject] = Triple[]
        end
        push!(subjects_map[triple.subject], triple)
    end

    # Convert to expanded JSON-LD nodes
    expanded_nodes = []

    for (subj, subj_triples) in subjects_map
        node = node_from_triples(subj, subj_triples)
        push!(expanded_nodes, node)
    end

    # Compact if context provided
    if !isnothing(context)
        # For Phase 1, skip compaction (will be implemented in Phase 3)
        # For now, just add context to output
        if length(expanded_nodes) == 1
            result = expanded_nodes[1]
            result["@context"] = context_to_dict(context)
            return JSON3.write(result, allow_inf=true)
        else
            result = Dict("@context" => context_to_dict(context), "@graph" => expanded_nodes)
            return JSON3.write(result, allow_inf=true)
        end
    end

    # Return expanded form
    result = length(expanded_nodes) == 1 ? expanded_nodes[1] : expanded_nodes
    return JSON3.write(result, allow_inf=true)
end

"""
    node_from_triples(subject::RDFNode, triples::Vector{Triple})::Dict

Create an expanded JSON-LD node from triples with a common subject.

# Arguments
- `subject::RDFNode` - The subject node
- `triples::Vector{Triple}` - All triples with this subject

# Returns
- `Dict` - Expanded JSON-LD node object
"""
function node_from_triples(subject::RDFNode, triples::Vector{Triple})::Dict
    node = Dict{String, Any}()

    # Add @id
    if subject isa IRI
        node["@id"] = subject.value
    elseif subject isa BlankNode
        node["@id"] = "_:$(subject.id)"
    end

    # Group by predicate
    by_predicate = Dict{IRI, Vector{RDFNode}}()
    for triple in triples
        if !haskey(by_predicate, triple.predicate)
            by_predicate[triple.predicate] = RDFNode[]
        end
        push!(by_predicate[triple.predicate], triple.object)
    end

    # Convert predicates
    for (pred, objects) in by_predicate
        if pred == RDF.type_
            # Special handling for rdf:type
            node["@type"] = [o.value for o in objects if o isa IRI]
        else
            # Regular property
            node[pred.value] = [node_to_jsonld_value(o) for o in objects]
        end
    end

    return node
end

"""
    node_to_jsonld_value(node::RDFNode)

Convert an RDF node to a JSON-LD value object.

# Arguments
- `node::RDFNode` - The RDF node to convert

# Returns
- JSON-LD value representation (Dict or simple value)
"""
function node_to_jsonld_value(node::RDFNode)
    if node isa IRI
        return Dict("@id" => node.value)
    elseif node isa BlankNode
        return Dict("@id" => "_:$(node.id)")
    elseif node isa Literal
        result = Dict{String, Any}("@value" => node.value)

        if !isnothing(node.language)
            result["@language"] = node.language
        elseif !isnothing(node.datatype)
            result["@type"] = node.datatype.value
        end

        return result
    end

    # Fallback
    return Dict("@value" => string(node))
end
