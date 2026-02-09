# JSON-LD Expansion Algorithm

using JSON3

"""
    expand(json_input, context::Union{Context, Nothing}=nothing)::Vector{Dict}

Expand a JSON-LD document, removing @context and converting all terms to full IRIs.

The expansion algorithm normalizes JSON-LD to a canonical form where:
- All properties are full IRIs
- All @context information is removed
- Values are normalized to @value, @id, or @type objects
- Result is always an array of node objects

# Arguments
- `json_input` - JSON-LD document (string, dict, or JSON3.Object)
- `context::Union{Context, Nothing}` - Optional context to use (if not in document)

# Returns
- `Vector{Dict}` - Array of expanded node objects

# Example
```julia
json = \"\"\"{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Person",
  "name": "Alice"
}\"\"\"
expanded = expand(json)
# Returns: [{"@type": ["http://schema.org/Person"], "http://schema.org/name": [{"@value": "Alice"}]}]
```
"""
function expand(json_input, context::Union{Context, Nothing}=nothing)::Vector{Dict}
    # Parse if string
    parsed = json_input isa String ? JSON3.read(json_input) : json_input

    # Convert JSON3.Object or other types to Dict for uniform handling
    if !(parsed isa Dict)
        # Convert Symbol keys to String keys
        parsed = Dict{String, Any}(String(k) => v for (k, v) in pairs(parsed))
    end

    # Extract context from document if present
    doc_context = haskey(parsed, "@context") ? parse_context_object(parsed["@context"]) : Context()

    # Merge with provided context
    active_context = isnothing(context) ? doc_context : merge_contexts(doc_context, context)

    # Expand the document
    expanded = expand_element(parsed, active_context)

    # Ensure result is array
    if expanded isa Vector
        return expanded
    else
        return [expanded]
    end
end

"""
    expand_element(element, context::Context)

Recursively expand a JSON-LD element (object, array, or scalar).

# Arguments
- `element` - The element to expand
- `context::Context` - The active context

# Returns
- Expanded element (Dict, Vector, or value object)
"""
function expand_element(element, context::Context)
    # Null
    if isnothing(element)
        return nothing
    end

    # Array
    if element isa Vector
        result = []
        for item in element
            expanded_item = expand_element(item, context)
            if !isnothing(expanded_item)
                if expanded_item isa Vector
                    append!(result, expanded_item)
                else
                    push!(result, expanded_item)
                end
            end
        end
        return result
    end

    # Scalar (number, string, boolean)
    if !(element isa Dict)
        return create_value_object(element)
    end

    # Object/Node
    return expand_object(element, context)
end

"""
    expand_object(obj::Dict, context::Context)::Dict

Expand a JSON-LD object to canonical form.

# Arguments
- `obj::Dict` - The object to expand
- `context::Context` - The active context

# Returns
- `Dict` - Expanded object with full IRIs
"""
function expand_object(obj::Dict, context::Context)::Dict
    # Skip if @context only
    if length(obj) == 1 && haskey(obj, "@context")
        return Dict()
    end

    result = Dict{String, Any}()

    for (key, value) in pairs(obj)
        key_str = string(key)

        # Skip @context
        if key_str == "@context"
            continue
        end

        # Handle @id
        if key_str == "@id"
            result["@id"] = expand_iri(string(value), context)
            continue
        end

        # Handle @type
        if key_str == "@type"
            if value isa AbstractArray
                result["@type"] = [expand_iri(string(v), context) for v in value]
            else
                result["@type"] = [expand_iri(string(value), context)]
            end
            continue
        end

        # Handle @value
        if key_str == "@value"
            result["@value"] = value
            continue
        end

        # Handle @language
        if key_str == "@language"
            result["@language"] = string(value)
            continue
        end

        # Handle other keywords
        if startswith(key_str, "@")
            result[key_str] = value
            continue
        end

        # Expand property IRI
        expanded_property = expand_iri(key_str, context)

        # Skip if couldn't expand and no vocab
        if expanded_property == key_str && isnothing(context.vocab)
            continue
        end

        # Expand value(s)
        expanded_value = expand_property_value(value, context, key_str)

        if !isnothing(expanded_value) && !isempty(expanded_value)
            # Always store as array for consistency
            if expanded_value isa Vector
                result[expanded_property] = expanded_value
            else
                result[expanded_property] = [expanded_value]
            end
        end
    end

    return result
end

"""
    expand_property_value(value, context::Context, property::String)

Expand a property value, handling scalars, objects, and arrays.

# Arguments
- `value` - The value to expand
- `context::Context` - The active context
- `property::String` - The property this value belongs to (for type coercion)

# Returns
- Expanded value(s)
"""
function expand_property_value(value, context::Context, property::String)
    # Check for type coercion in context
    type_coercion = nothing
    if haskey(context.terms, property)
        term_def = context.terms[property]
        type_coercion = term_def.type_mapping
    end

    # Array (handle both Vector and JSON3.Array)
    if value isa AbstractArray
        result = []
        for item in value
            expanded_item = expand_single_value(item, context, type_coercion)
            if !isnothing(expanded_item)
                push!(result, expanded_item)
            end
        end
        return result
    end

    # Single value
    return expand_single_value(value, context, type_coercion)
end

"""
    expand_single_value(value, context::Context, type_coercion::Union{String, Nothing})

Expand a single value based on its type and any type coercion.

# Arguments
- `value` - The value to expand
- `context::Context` - The active context
- `type_coercion::Union{String, Nothing}` - Type coercion from term definition

# Returns
- Expanded value (Dict with @value/@id/@type or expanded object)
"""
function expand_single_value(value, context::Context, type_coercion::Union{String, Nothing})
    # Null
    if isnothing(value)
        return nothing
    end

    # Object (handle both Dict and JSON3.Object)
    if value isa Dict || value isa JSON3.Object
        # Convert JSON3.Object to Dict if needed
        if !(value isa Dict)
            value = Dict{String, Any}(String(k) => v for (k, v) in pairs(value))
        end

        # Check if it's a value object
        if haskey(value, "@value")
            return value  # Already expanded
        end

        # Check if it's an ID reference
        if haskey(value, "@id")
            return Dict("@id" => expand_iri(string(value["@id"]), context))
        end

        # Nested node
        return expand_object(value, context)
    end

    # String
    if value isa String
        # Type coercion to @id
        if type_coercion == "@id"
            return Dict("@id" => expand_iri(value, context))
        end

        # Regular string value
        return create_value_object(value)
    end

    # Number or boolean
    return create_value_object(value)
end

"""
    create_value_object(value)::Dict

Create a @value object from a scalar value.

# Arguments
- `value` - The scalar value (string, number, boolean)

# Returns
- `Dict` - Value object with @value and optional @type
"""
function create_value_object(value)::Dict
    result = Dict{String, Any}("@value" => value)

    # Add type for typed literals
    if value isa Int
        result["@type"] = XSD.integer.value
    elseif value isa Float64
        result["@type"] = XSD.double.value
    elseif value isa Bool
        result["@type"] = XSD.boolean.value
    end
    # String gets no @type (plain literal)

    return result
end
