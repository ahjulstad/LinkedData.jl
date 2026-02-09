# RDF Triple Store with Hexastore indexing for efficient querying

# ============================================================================
# RDFStore - In-memory triple store with multiple indexes
# ============================================================================

mutable struct RDFStore
    # Three hexastore indexes for different access patterns
    # SPO: Subject -> Predicate -> Set of Objects
    spo::Dict{RDFNode, Dict{IRI, Set{RDFNode}}}
    # OPS: Object -> Predicate -> Set of Subjects
    ops::Dict{RDFNode, Dict{IRI, Set{RDFNode}}}
    # PSO: Predicate -> Subject -> Set of Objects
    pso::Dict{IRI, Dict{RDFNode, Set{RDFNode}}}

    # Namespace management
    namespaces::Dict{String, IRI}

    # Statistics for query optimization
    triple_count::Int
    predicate_counts::Dict{IRI, Int}

    function RDFStore()
        new(
            Dict{RDFNode, Dict{IRI, Set{RDFNode}}}(),
            Dict{RDFNode, Dict{IRI, Set{RDFNode}}}(),
            Dict{IRI, Dict{RDFNode, Set{RDFNode}}}(),
            Dict{String, IRI}(),
            0,
            Dict{IRI, Int}()
        )
    end
end

# Display method
function Base.show(io::IO, store::RDFStore)
    print(io, "RDFStore(", store.triple_count, " triples, ",
          length(store.namespaces), " namespaces)")
end

# ============================================================================
# Core Store Operations
# ============================================================================

"""
    add!(store::RDFStore, triple::Triple) -> RDFStore

Add a triple to the store, updating all indexes.
Returns the store for chaining.
"""
function add!(store::RDFStore, triple::Triple)::RDFStore
    s, p, o = triple.subject, triple.predicate, triple.object

    # Add to SPO index
    if !haskey(store.spo, s)
        store.spo[s] = Dict{IRI, Set{RDFNode}}()
    end
    if !haskey(store.spo[s], p)
        store.spo[s][p] = Set{RDFNode}()
    end
    if !(o in store.spo[s][p])
        push!(store.spo[s][p], o)

        # Only update counts and other indexes if this is a new triple
        store.triple_count += 1

        # Update predicate statistics
        store.predicate_counts[p] = get(store.predicate_counts, p, 0) + 1

        # Add to OPS index
        if !haskey(store.ops, o)
            store.ops[o] = Dict{IRI, Set{RDFNode}}()
        end
        if !haskey(store.ops[o], p)
            store.ops[o][p] = Set{RDFNode}()
        end
        push!(store.ops[o][p], s)

        # Add to PSO index
        if !haskey(store.pso, p)
            store.pso[p] = Dict{RDFNode, Set{RDFNode}}()
        end
        if !haskey(store.pso[p], s)
            store.pso[p][s] = Set{RDFNode}()
        end
        push!(store.pso[p][s], o)
    end

    return store
end

"""
    add!(store::RDFStore, subject, predicate, object) -> RDFStore

Convenience method to add a triple from individual components.
"""
function add!(store::RDFStore, subject::Union{IRI, BlankNode},
              predicate::IRI, object::RDFNode)::RDFStore
    return add!(store, Triple(subject, predicate, object))
end

"""
    add!(store::RDFStore, triples::Vector{Triple}) -> RDFStore

Add multiple triples to the store.
"""
function add!(store::RDFStore, triples::Vector{Triple})::RDFStore
    for triple in triples
        add!(store, triple)
    end
    return store
end

"""
    remove!(store::RDFStore, triple::Triple) -> RDFStore

Remove a triple from the store, updating all indexes.
Returns the store for chaining.
"""
function remove!(store::RDFStore, triple::Triple)::RDFStore
    s, p, o = triple.subject, triple.predicate, triple.object

    # Check if triple exists in SPO index
    if haskey(store.spo, s) && haskey(store.spo[s], p) && o in store.spo[s][p]
        # Remove from SPO index
        delete!(store.spo[s][p], o)
        if isempty(store.spo[s][p])
            delete!(store.spo[s], p)
        end
        if isempty(store.spo[s])
            delete!(store.spo, s)
        end

        # Remove from OPS index
        delete!(store.ops[o][p], s)
        if isempty(store.ops[o][p])
            delete!(store.ops[o], p)
        end
        if isempty(store.ops[o])
            delete!(store.ops, o)
        end

        # Remove from PSO index
        delete!(store.pso[p][s], o)
        if isempty(store.pso[p][s])
            delete!(store.pso[p], s)
        end
        if isempty(store.pso[p])
            delete!(store.pso, p)
        end

        # Update statistics
        store.triple_count -= 1
        store.predicate_counts[p] -= 1
        if store.predicate_counts[p] == 0
            delete!(store.predicate_counts, p)
        end
    end

    return store
end

"""
    has_triple(store::RDFStore, triple::Triple) -> Bool

Check if a triple exists in the store.
"""
function has_triple(store::RDFStore, triple::Triple)::Bool
    s, p, o = triple.subject, triple.predicate, triple.object
    return haskey(store.spo, s) && haskey(store.spo[s], p) && o in store.spo[s][p]
end

"""
    triples(store::RDFStore; subject=nothing, predicate=nothing, object=nothing) -> Vector{Triple}

Query triples from the store with optional filters.
Uses the most efficient index based on which parameters are provided.
"""
function triples(store::RDFStore; subject::Union{RDFNode, Nothing}=nothing,
                 predicate::Union{IRI, Nothing}=nothing,
                 object::Union{RDFNode, Nothing}=nothing)::Vector{Triple}

    result = Triple[]

    # Choose optimal query strategy based on bound variables
    if !isnothing(subject) && !isnothing(predicate) && !isnothing(object)
        # All bound - just check existence
        if has_triple(store, Triple(subject, predicate, object))
            push!(result, Triple(subject, predicate, object))
        end

    elseif !isnothing(subject) && !isnothing(predicate)
        # Use SPO index: subject + predicate -> objects
        if haskey(store.spo, subject) && haskey(store.spo[subject], predicate)
            for o in store.spo[subject][predicate]
                push!(result, Triple(subject, predicate, o))
            end
        end

    elseif !isnothing(object) && !isnothing(predicate)
        # Use OPS index: object + predicate -> subjects
        if haskey(store.ops, object) && haskey(store.ops[object], predicate)
            for s in store.ops[object][predicate]
                push!(result, Triple(s, predicate, object))
            end
        end

    elseif !isnothing(predicate) && !isnothing(subject)
        # Use PSO index: predicate + subject -> objects
        if haskey(store.pso, predicate) && haskey(store.pso[predicate], subject)
            for o in store.pso[predicate][subject]
                push!(result, Triple(subject, predicate, o))
            end
        end

    elseif !isnothing(subject)
        # Use SPO index: subject -> all predicates and objects
        if haskey(store.spo, subject)
            for (p, objects) in store.spo[subject]
                for o in objects
                    push!(result, Triple(subject, p, o))
                end
            end
        end

    elseif !isnothing(predicate)
        # Use PSO index: predicate -> all subjects and objects
        if haskey(store.pso, predicate)
            for (s, objects) in store.pso[predicate]
                for o in objects
                    push!(result, Triple(s, predicate, o))
                end
            end
        end

    elseif !isnothing(object)
        # Use OPS index: object -> all predicates and subjects
        if haskey(store.ops, object)
            for (p, subjects) in store.ops[object]
                for s in subjects
                    push!(result, Triple(s, p, object))
                end
            end
        end

    else
        # No filters - return all triples (use SPO index)
        for (s, predicates) in store.spo
            for (p, objects) in predicates
                for o in objects
                    push!(result, Triple(s, p, o))
                end
            end
        end
    end

    return result
end

# ============================================================================
# Namespace Management
# ============================================================================

"""
    register_namespace!(store::RDFStore, prefix::String, iri::IRI) -> RDFStore

Register a namespace prefix for abbreviation/expansion.
"""
function register_namespace!(store::RDFStore, prefix::String, iri::IRI)::RDFStore
    store.namespaces[prefix] = iri
    return store
end

"""
    expand(store::RDFStore, prefixed::String) -> IRI

Expand a prefixed name to a full IRI using registered namespaces.
Example: expand(store, "foaf:knows") -> IRI("http://xmlns.com/foaf/0.1/knows")
"""
function expand(store::RDFStore, prefixed::String)::IRI
    if occursin(':', prefixed)
        prefix, local_name = split(prefixed, ':', limit=2)
        if haskey(store.namespaces, prefix)
            return IRI(store.namespaces[prefix].value * local_name)
        end
    end
    throw(ArgumentError("Unknown prefix or invalid format: $prefixed"))
end

"""
    abbreviate(store::RDFStore, iri::IRI) -> Union{String, Nothing}

Try to abbreviate an IRI using registered namespaces.
Returns nothing if no matching namespace is found.
"""
function abbreviate(store::RDFStore, iri::IRI)::Union{String, Nothing}
    iri_str = iri.value
    for (prefix, namespace_iri) in store.namespaces
        ns_str = namespace_iri.value
        if startswith(iri_str, ns_str)
            local_name = iri_str[length(ns_str)+1:end]
            return prefix * ":" * local_name
        end
    end
    return nothing
end

# ============================================================================
# Statistics and Utilities
# ============================================================================

"""
    count_triples(store::RDFStore) -> Int

Return the total number of triples in the store.
"""
function count_triples(store::RDFStore)::Int
    return store.triple_count
end

"""
    count_subjects(store::RDFStore) -> Int

Return the number of unique subjects in the store.
"""
function count_subjects(store::RDFStore)::Int
    return length(store.spo)
end

"""
    count_predicates(store::RDFStore) -> Int

Return the number of unique predicates in the store.
"""
function count_predicates(store::RDFStore)::Int
    return length(store.pso)
end

"""
    count_objects(store::RDFStore) -> Int

Return the number of unique objects in the store.
"""
function count_objects(store::RDFStore)::Int
    return length(store.ops)
end

"""
    get_predicate_count(store::RDFStore, predicate::IRI) -> Int

Get the number of triples with a specific predicate (for query optimization).
"""
function get_predicate_count(store::RDFStore, predicate::IRI)::Int
    return get(store.predicate_counts, predicate, 0)
end

# Iterator interface for efficient traversal
Base.length(store::RDFStore) = store.triple_count
Base.iterate(store::RDFStore) = iterate(triples(store))
Base.iterate(store::RDFStore, state) = iterate(triples(store), state)
