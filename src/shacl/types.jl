# SHACL (Shapes Constraint Language) Types and Structures

# ============================================================================
# Abstract Types
# ============================================================================

abstract type Shape end
abstract type Target end
abstract type Constraint end

# ============================================================================
# Shape Types
# ============================================================================

"""
PropertyShape - Validates values of a property
"""
mutable struct PropertyShape <: Shape
    id::Union{IRI, BlankNode, Nothing}
    path::IRI  # Property path
    constraints::Vector{Constraint}
    message::Union{String, Nothing}
    severity::Symbol  # :Violation, :Warning, :Info
    name::Union{String, Nothing}

    function PropertyShape(path::IRI;
                          id::Union{IRI, BlankNode, Nothing}=nothing,
                          constraints::Vector{<:Constraint}=Constraint[],
                          message::Union{String, Nothing}=nothing,
                          severity::Symbol=:Violation,
                          name::Union{String, Nothing}=nothing)
        new(id, path, convert(Vector{Constraint}, constraints), message, severity, name)
    end
end

"""
NodeShape - Validates nodes directly
"""
mutable struct NodeShape <: Shape
    id::Union{IRI, BlankNode}
    targets::Vector{Target}
    constraints::Vector{Constraint}
    property_shapes::Vector{PropertyShape}
    message::Union{String, Nothing}
    severity::Symbol  # :Violation, :Warning, :Info
    deactivated::Bool

    function NodeShape(id::Union{IRI, BlankNode};
                      targets::Vector{<:Target}=Target[],
                      constraints::Vector{<:Constraint}=Constraint[],
                      property_shapes::Vector{PropertyShape}=PropertyShape[],
                      message::Union{String, Nothing}=nothing,
                      severity::Symbol=:Violation,
                      deactivated::Bool=false)
        new(id, convert(Vector{Target}, targets), convert(Vector{Constraint}, constraints),
            property_shapes, message, severity, deactivated)
    end
end

# ============================================================================
# Target Types
# ============================================================================

"""
Target nodes that are instances of a class
"""
struct TargetClass <: Target
    class_iri::IRI
end

"""
Target specific nodes
"""
struct TargetNode <: Target
    node::RDFNode
end

"""
Target subjects of triples with given predicate
"""
struct TargetSubjectsOf <: Target
    predicate::IRI
end

"""
Target objects of triples with given predicate
"""
struct TargetObjectsOf <: Target
    predicate::IRI
end

# ============================================================================
# Cardinality Constraints
# ============================================================================

"""
Minimum number of values
"""
struct MinCount <: Constraint
    value::Int
end

"""
Maximum number of values
"""
struct MaxCount <: Constraint
    value::Int
end

# ============================================================================
# Value Type Constraints
# ============================================================================

"""
Values must have specific datatype
"""
struct Datatype <: Constraint
    datatype::IRI
end

"""
Values must be instances of a class
"""
struct Class <: Constraint
    class_iri::IRI
end

"""
Values must be of specific node kind
"""
struct NodeKind <: Constraint
    kind::Symbol  # :IRI, :BlankNode, :Literal, :BlankNodeOrIRI, :BlankNodeOrLiteral, :IRIOrLiteral
end

# ============================================================================
# String Constraints
# ============================================================================

"""
Minimum string length
"""
struct MinLength <: Constraint
    value::Int
end

"""
Maximum string length
"""
struct MaxLength <: Constraint
    value::Int
end

"""
String must match regex pattern
"""
struct Pattern <: Constraint
    pattern::String
    flags::Union{String, Nothing}

    Pattern(pattern::String, flags::Union{String, Nothing}=nothing) = new(pattern, flags)
end

"""
String must match language tag
"""
struct LanguageIn <: Constraint
    languages::Vector{String}
end

"""
String must have exactly this value
"""
struct HasValue <: Constraint
    value::RDFNode
end

"""
String must be one of these values
"""
struct In <: Constraint
    values::Vector{RDFNode}
end

# ============================================================================
# Numeric Constraints
# ============================================================================

"""
Minimum value (inclusive)
"""
struct MinInclusive <: Constraint
    value::Union{Int, Float64, String}  # Can be literal value
end

"""
Maximum value (inclusive)
"""
struct MaxInclusive <: Constraint
    value::Union{Int, Float64, String}
end

"""
Minimum value (exclusive)
"""
struct MinExclusive <: Constraint
    value::Union{Int, Float64, String}
end

"""
Maximum value (exclusive)
"""
struct MaxExclusive <: Constraint
    value::Union{Int, Float64, String}
end

# ============================================================================
# Property Pair Constraints
# ============================================================================

"""
Property values must equal values of another property
"""
struct Equals <: Constraint
    property::IRI
end

"""
Property values must be disjoint from another property
"""
struct Disjoint <: Constraint
    property::IRI
end

"""
Property values must be less than values of another property
"""
struct LessThan <: Constraint
    property::IRI
end

"""
Property values must be less than or equal to values of another property
"""
struct LessThanOrEquals <: Constraint
    property::IRI
end

# ============================================================================
# Logical Constraints
# ============================================================================

"""
All constraints must be satisfied (AND)
"""
struct And <: Constraint
    shapes::Vector{Shape}
end

"""
At least one constraint must be satisfied (OR)
"""
struct Or <: Constraint
    shapes::Vector{Shape}
end

"""
Constraint must not be satisfied (NOT)
"""
struct Not <: Constraint
    shape::Shape
end

"""
Exactly one constraint must be satisfied (XOR)
"""
struct Xone <: Constraint
    shapes::Vector{Shape}
end

# ============================================================================
# Other Constraints
# ============================================================================

"""
Values must be closed (only specified properties allowed)
"""
struct Closed <: Constraint
    closed::Bool
    ignored_properties::Vector{IRI}

    Closed(closed::Bool=true, ignored_properties::Vector{IRI}=IRI[]) = new(closed, ignored_properties)
end

"""
Values must have exactly these property values
"""
struct UniqueLang <: Constraint
    unique_lang::Bool

    UniqueLang(unique_lang::Bool=true) = new(unique_lang)
end

# ============================================================================
# Validation Results
# ============================================================================

"""
Result of validating a single focus node against a constraint
"""
struct ValidationResult
    focus_node::RDFNode
    result_path::Union{IRI, Nothing}
    value::Union{RDFNode, Nothing}
    source_constraint::Constraint
    source_shape::Shape
    message::Union{String, Nothing}
    severity::Symbol  # :Violation, :Warning, :Info
    detail::Union{String, Nothing}

    function ValidationResult(focus_node::RDFNode,
                             source_constraint::Constraint,
                             source_shape::Shape;
                             result_path::Union{IRI, Nothing}=nothing,
                             value::Union{RDFNode, Nothing}=nothing,
                             message::Union{String, Nothing}=nothing,
                             severity::Symbol=:Violation,
                             detail::Union{String, Nothing}=nothing)
        new(focus_node, result_path, value, source_constraint, source_shape,
            message, severity, detail)
    end
end

"""
Report containing all validation results
"""
struct ValidationReport
    conforms::Bool
    results::Vector{ValidationResult}

    ValidationReport(conforms::Bool, results::Vector{ValidationResult}=ValidationResult[]) =
        new(conforms, results)
end

# ============================================================================
# Helper Functions
# ============================================================================

"""
Get all focus nodes for a shape from a store
"""
function get_target_nodes(store::RDFStore, shape::NodeShape)::Vector{RDFNode}
    nodes = RDFNode[]

    for target in shape.targets
        if target isa TargetClass
            # Find all instances of the class
            for triple in triples(store; predicate=RDF.type_, object=target.class_iri)
                push!(nodes, triple.subject)
            end
        elseif target isa TargetNode
            # Direct node
            push!(nodes, target.node)
        elseif target isa TargetSubjectsOf
            # All subjects of triples with this predicate
            for triple in triples(store; predicate=target.predicate)
                push!(nodes, triple.subject)
            end
        elseif target isa TargetObjectsOf
            # All objects of triples with this predicate
            for triple in triples(store; predicate=target.predicate)
                push!(nodes, triple.object)
            end
        end
    end

    return unique(nodes)
end

"""
Get values of a property for a node
"""
function get_property_values(store::RDFStore, node::RDFNode, property::IRI)::Vector{RDFNode}
    values = RDFNode[]

    for triple in triples(store; subject=node, predicate=property)
        push!(values, triple.object)
    end

    return values
end

"""
Check if a node is an instance of a class (with subclass inference)
"""
function is_instance_of(store::RDFStore, node::RDFNode, class_iri::IRI)::Bool
    # Direct instance check
    for triple in triples(store; subject=node, predicate=RDF.type_)
        if triple.object == class_iri
            return true
        end

        # TODO: Add subclass inference (rdfs:subClassOf reasoning)
        # For now, just direct instance check
    end

    return false
end

"""
Compare RDF node values numerically
"""
function compare_numeric(a::RDFNode, b::Union{Int, Float64, String, RDFNode}, op::Symbol)::Bool
    # Extract numeric values
    a_val = try_parse_numeric(a)
    b_val = if b isa RDFNode
        try_parse_numeric(b)
    elseif b isa String
        try
            parse(Float64, b)
        catch
            return false
        end
    else
        Float64(b)
    end

    isnothing(a_val) || isnothing(b_val) && return false

    if op == :lt
        return a_val < b_val
    elseif op == :le
        return a_val <= b_val
    elseif op == :gt
        return a_val > b_val
    elseif op == :ge
        return a_val >= b_val
    elseif op == :eq
        return a_val == b_val
    else
        return false
    end
end

"""
Try to parse an RDF node as a number
"""
function try_parse_numeric(node::RDFNode)::Union{Float64, Nothing}
    node isa Literal || return nothing

    try
        return parse(Float64, node.value)
    catch
        return nothing
    end
end
