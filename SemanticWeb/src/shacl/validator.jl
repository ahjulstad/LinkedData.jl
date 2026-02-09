# SHACL Validation Engine

"""
    validate(data_store::RDFStore, shapes_store::RDFStore) -> ValidationReport
    validate(data_store::RDFStore, shapes::Vector{Shape}) -> ValidationReport

Validate RDF data against SHACL shapes.
"""
function validate(data_store::RDFStore, shapes::Vector{<:Shape})::ValidationReport
    results = ValidationResult[]

    for shape in shapes
        if shape isa NodeShape && !shape.deactivated
            append!(results, validate_node_shape(data_store, shape))
        end
    end

    conforms = isempty(results) || all(r -> r.severity != :Violation, results)

    return ValidationReport(conforms, results)
end

# Convenience method for validating with shapes in a separate store
function validate(_data_store::RDFStore, _shapes_store::RDFStore)::ValidationReport
    # TODO: Parse shapes from shapes_store
    # For now, this is a placeholder
    throw(ArgumentError("Shape parsing from RDF store not yet implemented. Use validate(store, shapes::Vector{Shape}) instead."))
end

# ============================================================================
# Node Shape Validation
# ============================================================================

"""
Validate a node shape against all target nodes
"""
function validate_node_shape(store::RDFStore, shape::NodeShape)::Vector{ValidationResult}
    results = ValidationResult[]

    # Get target nodes
    target_nodes = get_target_nodes(store, shape)

    # Validate each target node
    for node in target_nodes
        append!(results, validate_node_against_shape(store, node, shape))
    end

    return results
end

"""
Validate a single node against a node shape
"""
function validate_node_against_shape(store::RDFStore, node::RDFNode, shape::NodeShape)::Vector{ValidationResult}
    results = ValidationResult[]

    # Validate node-level constraints
    for constraint in shape.constraints
        violations = validate_constraint(store, node, nothing, constraint, shape)
        append!(results, violations)
    end

    # Validate property shapes
    for prop_shape in shape.property_shapes
        violations = validate_property_shape(store, node, prop_shape)
        append!(results, violations)
    end

    return results
end

# ============================================================================
# Property Shape Validation
# ============================================================================

"""
Validate a property shape for a node
"""
function validate_property_shape(store::RDFStore, node::RDFNode, shape::PropertyShape)::Vector{ValidationResult}
    results = ValidationResult[]

    # Get property values
    values = get_property_values(store, node, shape.path)

    # Validate each constraint
    for constraint in shape.constraints
        # Check cardinality constraints against all values
        if constraint isa MinCount || constraint isa MaxCount || constraint isa HasValue || constraint isa In
            violations = validate_constraint(store, node, shape.path, constraint, shape, values)
            append!(results, violations)
        else
            # Validate each value individually
            for value in values
                violations = validate_constraint(store, node, shape.path, constraint, shape, RDFNode[value])
                append!(results, violations)
            end
        end
    end

    return results
end

# ============================================================================
# Constraint Validation
# ============================================================================

"""
Validate a constraint
"""
function validate_constraint(store::RDFStore,
                            focus_node::RDFNode,
                            path::Union{IRI, Nothing},
                            constraint::Constraint,
                            shape::Shape,
                            values::Vector{RDFNode}=RDFNode[])::Vector{ValidationResult}

    # Cardinality constraints
    if constraint isa MinCount
        return validate_min_count(focus_node, path, constraint, shape, values)
    elseif constraint isa MaxCount
        return validate_max_count(focus_node, path, constraint, shape, values)

    # Value type constraints
    elseif constraint isa Datatype
        return validate_datatype(focus_node, path, constraint, shape, values)
    elseif constraint isa Class
        return validate_class(store, focus_node, path, constraint, shape, values)
    elseif constraint isa NodeKind
        return validate_node_kind(focus_node, path, constraint, shape, values)

    # String constraints
    elseif constraint isa MinLength
        return validate_min_length(focus_node, path, constraint, shape, values)
    elseif constraint isa MaxLength
        return validate_max_length(focus_node, path, constraint, shape, values)
    elseif constraint isa Pattern
        return validate_pattern(focus_node, path, constraint, shape, values)
    elseif constraint isa LanguageIn
        return validate_language_in(focus_node, path, constraint, shape, values)
    elseif constraint isa HasValue
        return validate_has_value(focus_node, path, constraint, shape, values)
    elseif constraint isa In
        return validate_in(focus_node, path, constraint, shape, values)

    # Numeric constraints
    elseif constraint isa MinInclusive
        return validate_min_inclusive(focus_node, path, constraint, shape, values)
    elseif constraint isa MaxInclusive
        return validate_max_inclusive(focus_node, path, constraint, shape, values)
    elseif constraint isa MinExclusive
        return validate_min_exclusive(focus_node, path, constraint, shape, values)
    elseif constraint isa MaxExclusive
        return validate_max_exclusive(focus_node, path, constraint, shape, values)

    # Property pair constraints
    elseif constraint isa Equals
        return validate_equals(store, focus_node, path, constraint, shape, values)
    elseif constraint isa Disjoint
        return validate_disjoint(store, focus_node, path, constraint, shape, values)

    # Logical constraints
    elseif constraint isa And
        return validate_and(store, focus_node, path, constraint, shape)
    elseif constraint isa Or
        return validate_or(store, focus_node, path, constraint, shape)
    elseif constraint isa Not
        return validate_not(store, focus_node, path, constraint, shape)

    else
        @warn "Unknown constraint type: $(typeof(constraint))"
        return ValidationResult[]
    end
end

# ============================================================================
# Cardinality Constraint Implementations
# ============================================================================

function validate_min_count(focus_node::RDFNode, path::Union{IRI, Nothing},
                           constraint::MinCount, shape::Shape,
                           values::Vector{RDFNode})::Vector{ValidationResult}
    if length(values) < constraint.value
        message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                  "Property has $(length(values)) values but requires at least $(constraint.value)"
        return [ValidationResult(focus_node, constraint, shape,
                               result_path=path,
                               message=message,
                               severity=shape isa PropertyShape ? shape.severity : :Violation)]
    end
    return ValidationResult[]
end

function validate_max_count(focus_node::RDFNode, path::Union{IRI, Nothing},
                           constraint::MaxCount, shape::Shape,
                           values::Vector{RDFNode})::Vector{ValidationResult}
    if length(values) > constraint.value
        message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                  "Property has $(length(values)) values but allows at most $(constraint.value)"
        return [ValidationResult(focus_node, constraint, shape,
                               result_path=path,
                               message=message,
                               severity=shape isa PropertyShape ? shape.severity : :Violation)]
    end
    return ValidationResult[]
end

# ============================================================================
# Value Type Constraint Implementations
# ============================================================================

function validate_datatype(focus_node::RDFNode, path::Union{IRI, Nothing},
                          constraint::Datatype, shape::Shape,
                          values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if !(value isa Literal) || isnothing(value.datatype) || value.datatype != constraint.datatype
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Value must have datatype $(constraint.datatype.value)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

function validate_class(store::RDFStore, focus_node::RDFNode, path::Union{IRI, Nothing},
                       constraint::Class, shape::Shape,
                       values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if !is_instance_of(store, value, constraint.class_iri)
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Value must be an instance of class $(constraint.class_iri.value)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

function validate_node_kind(focus_node::RDFNode, path::Union{IRI, Nothing},
                           constraint::NodeKind, shape::Shape,
                           values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        valid = if constraint.kind == :IRI
            value isa IRI
        elseif constraint.kind == :BlankNode
            value isa BlankNode
        elseif constraint.kind == :Literal
            value isa Literal
        elseif constraint.kind == :BlankNodeOrIRI
            value isa Union{BlankNode, IRI}
        elseif constraint.kind == :BlankNodeOrLiteral
            value isa Union{BlankNode, Literal}
        elseif constraint.kind == :IRIOrLiteral
            value isa Union{IRI, Literal}
        else
            false
        end

        if !valid
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Value must be of node kind $(constraint.kind)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

# ============================================================================
# String Constraint Implementations
# ============================================================================

function validate_min_length(focus_node::RDFNode, path::Union{IRI, Nothing},
                            constraint::MinLength, shape::Shape,
                            values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if value isa Literal && length(value.value) < constraint.value
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "String length $(length(value.value)) is less than minimum $(constraint.value)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

function validate_max_length(focus_node::RDFNode, path::Union{IRI, Nothing},
                            constraint::MaxLength, shape::Shape,
                            values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if value isa Literal && length(value.value) > constraint.value
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "String length $(length(value.value)) exceeds maximum $(constraint.value)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

function validate_pattern(focus_node::RDFNode, path::Union{IRI, Nothing},
                         constraint::Pattern, shape::Shape,
                         values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    regex = try
        Regex(constraint.pattern)
    catch
        @warn "Invalid regex pattern: $(constraint.pattern)"
        return results
    end

    for value in values
        if value isa Literal && isnothing(match(regex, value.value))
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Value does not match pattern $(constraint.pattern)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

function validate_language_in(focus_node::RDFNode, path::Union{IRI, Nothing},
                             constraint::LanguageIn, shape::Shape,
                             values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if value isa Literal
            lang = value.language
            if !isnothing(lang) && !(lang in constraint.languages)
                message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                          "Language tag $lang not in allowed languages"
                push!(results, ValidationResult(focus_node, constraint, shape,
                                              result_path=path,
                                              value=value,
                                              message=message,
                                              severity=shape isa PropertyShape ? shape.severity : :Violation))
            end
        end
    end

    return results
end

function validate_has_value(focus_node::RDFNode, path::Union{IRI, Nothing},
                           constraint::HasValue, shape::Shape,
                           values::Vector{RDFNode})::Vector{ValidationResult}
    if constraint.value in values
        return ValidationResult[]
    else
        message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                  "Required value $(constraint.value) not found"
        return [ValidationResult(focus_node, constraint, shape,
                               result_path=path,
                               message=message,
                               severity=shape isa PropertyShape ? shape.severity : :Violation)]
    end
end

function validate_in(focus_node::RDFNode, path::Union{IRI, Nothing},
                    constraint::In, shape::Shape,
                    values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if !(value in constraint.values)
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Value not in allowed list"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

# ============================================================================
# Numeric Constraint Implementations
# ============================================================================

function validate_min_inclusive(focus_node::RDFNode, path::Union{IRI, Nothing},
                               constraint::MinInclusive, shape::Shape,
                               values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if !compare_numeric(value, constraint.value, :ge)
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Value must be >= $(constraint.value)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

function validate_max_inclusive(focus_node::RDFNode, path::Union{IRI, Nothing},
                               constraint::MaxInclusive, shape::Shape,
                               values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if !compare_numeric(value, constraint.value, :le)
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Value must be <= $(constraint.value)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

function validate_min_exclusive(focus_node::RDFNode, path::Union{IRI, Nothing},
                               constraint::MinExclusive, shape::Shape,
                               values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if !compare_numeric(value, constraint.value, :gt)
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Value must be > $(constraint.value)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

function validate_max_exclusive(focus_node::RDFNode, path::Union{IRI, Nothing},
                               constraint::MaxExclusive, shape::Shape,
                               values::Vector{RDFNode})::Vector{ValidationResult}
    results = ValidationResult[]

    for value in values
        if !compare_numeric(value, constraint.value, :lt)
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Value must be < $(constraint.value)"
            push!(results, ValidationResult(focus_node, constraint, shape,
                                          result_path=path,
                                          value=value,
                                          message=message,
                                          severity=shape isa PropertyShape ? shape.severity : :Violation))
        end
    end

    return results
end

# ============================================================================
# Property Pair Constraint Implementations
# ============================================================================

function validate_equals(store::RDFStore, focus_node::RDFNode, path::Union{IRI, Nothing},
                        constraint::Equals, shape::Shape,
                        values::Vector{RDFNode})::Vector{ValidationResult}
    other_values = get_property_values(store, focus_node, constraint.property)

    if Set(values) != Set(other_values)
        message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                  "Property values must equal values of $(constraint.property.value)"
        return [ValidationResult(focus_node, constraint, shape,
                               result_path=path,
                               message=message,
                               severity=shape isa PropertyShape ? shape.severity : :Violation)]
    end

    return ValidationResult[]
end

function validate_disjoint(store::RDFStore, focus_node::RDFNode, path::Union{IRI, Nothing},
                          constraint::Disjoint, shape::Shape,
                          values::Vector{RDFNode})::Vector{ValidationResult}
    other_values = get_property_values(store, focus_node, constraint.property)
    intersection = intersect(Set(values), Set(other_values))

    if !isempty(intersection)
        message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                  "Property values must be disjoint from $(constraint.property.value)"
        return [ValidationResult(focus_node, constraint, shape,
                               result_path=path,
                               message=message,
                               severity=shape isa PropertyShape ? shape.severity : :Violation)]
    end

    return ValidationResult[]
end

# ============================================================================
# Logical Constraint Implementations
# ============================================================================

function validate_and(store::RDFStore, focus_node::RDFNode, path::Union{IRI, Nothing},
                     constraint::And, shape::Shape)::Vector{ValidationResult}
    results = ValidationResult[]

    for sub_shape in constraint.shapes
        if sub_shape isa NodeShape
            append!(results, validate_node_against_shape(store, focus_node, sub_shape))
        end
    end

    return results
end

function validate_or(store::RDFStore, focus_node::RDFNode, path::Union{IRI, Nothing},
                    constraint::Or, shape::Shape)::Vector{ValidationResult}
    # At least one shape must validate without violations
    for sub_shape in constraint.shapes
        if sub_shape isa NodeShape
            violations = validate_node_against_shape(store, focus_node, sub_shape)
            if isempty(violations)
                return ValidationResult[]  # At least one passed
            end
        end
    end

    # None passed
    message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
              "Node must satisfy at least one of the OR constraints"
    return [ValidationResult(focus_node, constraint, shape,
                           result_path=path,
                           message=message,
                           severity=shape isa PropertyShape ? shape.severity : :Violation)]
end

function validate_not(store::RDFStore, focus_node::RDFNode, path::Union{IRI, Nothing},
                     constraint::Not, shape::Shape)::Vector{ValidationResult}
    if constraint.shape isa NodeShape
        violations = validate_node_against_shape(store, focus_node, constraint.shape)

        if !isempty(violations)
            return ValidationResult[]  # NOT constraint satisfied
        else
            # Shape validated, but it shouldn't
            message = shape isa PropertyShape && !isnothing(shape.message) ? shape.message :
                      "Node must NOT satisfy the constraint"
            return [ValidationResult(focus_node, constraint, shape,
                                   result_path=path,
                                   message=message,
                                   severity=shape isa PropertyShape ? shape.severity : :Violation)]
        end
    end

    return ValidationResult[]
end
