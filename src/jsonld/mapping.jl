# JSON-LD Struct Mapping

using JSON3

"""
    from_jsonld(json::String)::JSONLDObject

Parse JSON-LD into a dynamic JSONLDObject without knowing the type in advance.

This is useful for exploratory analysis or when the schema is not known upfront.
For processing many objects of the same type, use `from_jsonld(Type{T}, json)` instead.

# Arguments
- `json::String` - JSON-LD document as string

# Returns
- `JSONLDObject` - Dynamic wrapper with property access

# Example
```julia
json = \"\"\"{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Person",
  "name": "Alice",
  "age": 30
}\"\"\"

obj = from_jsonld(json)
println(obj.name)  # "Alice"
println(obj.age)   # 30
println(obj.type)  # ["http://schema.org/Person"]
```
"""
function from_jsonld(json::String)::JSONLDObject
    # Parse and expand
    expanded = expand(json)

    # Take first node (or create empty if none)
    node = isempty(expanded) ? Dict{String, Any}() : expanded[1]

    # Extract context from original JSON
    parsed = JSON3.read(json)
    context = haskey(parsed, Symbol("@context")) ? parse_context(json) : nothing

    return JSONLDObject(node, context)
end

"""
    from_jsonld(::Type{T}, json::String; options::ConversionOptions=ConversionOptions()) where T

Parse JSON-LD into a specific Julia struct type for optimized processing.

This is the compiled/optimized path for when you know the type and want to
process many objects efficiently. The type mapping is cached for reuse.

# Arguments
- `T::Type` - The Julia struct type to parse into
- `json::String` - JSON-LD document as string
- `options::ConversionOptions` - Optional conversion settings

# Returns
- Instance of type `T`

# Example
```julia
# Define a struct
struct Person
    id::Union{String, Nothing}
    name::String
    age::Union{Int, Nothing}
end

# Parse JSON-LD into the struct
json = \"\"\"{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Person",
  "name": "Alice",
  "age": 30
}\"\"\"

person = from_jsonld(Person, json)
println(person.name)  # "Alice"
println(person.age)   # 30
```
"""
function from_jsonld(::Type{T}, json::String;
                     options::ConversionOptions=ConversionOptions()) where T
    # Parse and expand
    expanded = expand(json, options.context)

    # Take first node
    if isempty(expanded)
        throw(ArgumentError("Empty JSON-LD document"))
    end
    node = expanded[1]

    # Get or infer type mapping
    mapping = get_type_mapping(T)

    # Build struct from node
    return node_to_struct(T, node, mapping)
end

"""
    get_type_mapping(::Type{T})::TypeMapping where T

Get or infer the type mapping for a Julia struct.

Checks the TYPE_REGISTRY first (populated by @jsonld macro),
then SHACL_GENERATED_TYPES, and finally infers from the struct definition.

# Arguments
- `T::Type` - The struct type

# Returns
- `TypeMapping` - The mapping information
"""
function get_type_mapping(::Type{T})::TypeMapping where T
    # Check @jsonld registry
    if haskey(TYPE_REGISTRY, T)
        return TYPE_REGISTRY[T]
    end

    # Check SHACL-generated types
    if haskey(SHACL_GENERATED_TYPES, T)
        return SHACL_GENERATED_TYPES[T]
    end

    # Infer from struct definition
    return infer_type_mapping(T)
end

"""
    infer_type_mapping(::Type{T})::TypeMapping where T

Infer a TypeMapping from a Julia struct definition using conventions.

Conventions:
- snake_case field names → camelCase JSON-LD properties
- Field named `id` → @id
- Field named `type` or `types` → @type
- Struct name → RDF type (with default vocab)

# Arguments
- `T::Type` - The struct type to analyze

# Returns
- `TypeMapping` - Inferred mapping
"""
function infer_type_mapping(::Type{T})::TypeMapping where T
    field_mappings = Dict{Symbol, String}()
    id_field = nothing

    for field_name in fieldnames(T)
        # Check for special fields
        if field_name == :id
            id_field = :id
            continue  # Don't map to a regular property
        elseif field_name == :type || field_name == :types
            continue  # Skip @type field
        end

        # Convert snake_case → camelCase
        jsonld_name = to_camel_case(string(field_name))
        field_mappings[field_name] = jsonld_name
    end

    # Infer RDF type from struct name (use schema.org as default)
    rdf_type = IRI("http://schema.org/$(string(T))")

    # Create default context with schema.org vocab
    context = Context(vocab=IRI("http://schema.org/"))

    return TypeMapping(T, rdf_type, context, field_mappings, id_field)
end

"""
    to_camel_case(snake::String)::String

Convert snake_case to camelCase.

# Example
```julia
to_camel_case("first_name")  # "firstName"
to_camel_case("age")         # "age"
```
"""
function to_camel_case(snake::String)::String
    parts = split(snake, '_')
    if length(parts) == 1
        return snake  # Already camelCase or single word
    end

    return parts[1] * join(titlecase.(parts[2:end]))
end

"""
    node_to_struct(::Type{T}, node::Dict, mapping::TypeMapping) where T

Convert an expanded JSON-LD node to a Julia struct instance.

# Arguments
- `T::Type` - The target struct type
- `node::Dict` - Expanded JSON-LD node
- `mapping::TypeMapping` - The type mapping to use

# Returns
- Instance of type `T`
"""
function node_to_struct(::Type{T}, node::Dict, mapping::TypeMapping) where T
    # Verify @type matches (if present)
    if haskey(node, "@type")
        node_types = node["@type"]
        rdf_type_str = mapping.rdf_type.value

        if !(node_types isa Vector ? rdf_type_str in node_types : node_types == rdf_type_str)
            @warn "JSON-LD @type does not match expected type" expected=rdf_type_str found=node_types
        end
    end

    # Build field values
    field_values = []

    for field_name in fieldnames(T)
        field_type = fieldtype(T, field_name)

        # Handle @id field
        if field_name == mapping.id_field
            id_val = get(node, "@id", nothing)
            push!(field_values, id_val)
            continue
        end

        # Handle @type field
        if field_name == :type || field_name == :types
            types = get(node, "@type", String[])
            types_array = types isa Vector ? types : [types]
            push!(field_values, field_name == :type ? (isempty(types_array) ? nothing : types_array[1]) : types_array)
            continue
        end

        # Handle regular property
        if haskey(mapping.field_mappings, field_name)
            property_iri = mapping.field_mappings[field_name]

            # Expand property IRI with context
            if mapping.context isa Context
                property_iri = expand_iri(property_iri, mapping.context)
            end

            if haskey(node, property_iri)
                values = node[property_iri]
                value = jsonld_value_to_julia(values, field_type)
                push!(field_values, value)
            else
                # Field not present - use default
                push!(field_values, nothing)
            end
        else
            # Field not mapped - use default
            push!(field_values, nothing)
        end
    end

    # Construct struct
    return T(field_values...)
end

"""
    jsonld_value_to_julia(value, target_type::Type)

Convert a JSON-LD value (from expanded form) to a Julia value of the target type.

# Arguments
- `value` - The JSON-LD value (can be array or single value)
- `target_type::Type` - The target Julia type

# Returns
- Converted value matching target_type
"""
function jsonld_value_to_julia(value, target_type::Type)
    # Handle Vector types
    if target_type <: Vector
        element_type = eltype(target_type)
        values_array = value isa Vector ? value : [value]
        return [jsonld_single_value_to_julia(v, element_type) for v in values_array]
    end

    # Handle Union{T, Nothing}
    if target_type isa Union
        # Extract non-Nothing type
        non_nothing_type = target_type.a == Nothing ? target_type.b : target_type.a
        if value isa Vector
            # Take first value
            return isempty(value) ? nothing : jsonld_single_value_to_julia(value[1], non_nothing_type)
        else
            return jsonld_single_value_to_julia(value, non_nothing_type)
        end
    end

    # Handle single value
    if value isa Vector
        return isempty(value) ? nothing : jsonld_single_value_to_julia(value[1], target_type)
    else
        return jsonld_single_value_to_julia(value, target_type)
    end
end

"""
    jsonld_single_value_to_julia(value, target_type::Type)

Convert a single JSON-LD value object to Julia value.

# Arguments
- `value` - Single JSON-LD value (Dict with @value/@id or plain value)
- `target_type::Type` - Target Julia type

# Returns
- Converted value
"""
function jsonld_single_value_to_julia(value, target_type::Type)
    # Handle value objects
    if value isa Dict
        if haskey(value, "@value")
            return convert_literal_value(value["@value"], target_type)
        elseif haskey(value, "@id")
            # IRI reference
            if target_type == IRI
                return IRI(value["@id"])
            else
                return value["@id"]
            end
        else
            # Nested object - would need recursive handling
            return value
        end
    end

    # Plain value
    return convert_literal_value(value, target_type)
end

"""
    convert_literal_value(value, target_type::Type)

Convert a literal value to the target Julia type.

# Arguments
- `value` - The literal value
- `target_type::Type` - Target type

# Returns
- Converted value
"""
function convert_literal_value(value, target_type::Type)
    if target_type == String
        return string(value)
    elseif target_type == Int
        return value isa Int ? value : parse(Int, string(value))
    elseif target_type == Float64
        return value isa Float64 ? value : parse(Float64, string(value))
    elseif target_type == Bool
        return value isa Bool ? value : parse(Bool, string(value))
    else
        return value
    end
end

"""
    to_jsonld(obj; options::ConversionOptions=ConversionOptions())::String

Serialize a Julia struct or JSONLDObject to JSON-LD string.

For structs, uses the type mapping (from @jsonld or inferred).
For JSONLDObject, serializes the wrapped data.

# Arguments
- `obj` - The object to serialize (struct or JSONLDObject)
- `options::ConversionOptions` - Optional conversion settings

# Returns
- `String` - JSON-LD document

# Example
```julia
person = Person(nothing, "Alice", 30)
json = to_jsonld(person)
```
"""
function to_jsonld(obj::JSONLDObject; options::ConversionOptions=ConversionOptions())::String
    # Serialize wrapped data
    if options.compact && !isnothing(obj.context)
        # Would need compaction implementation
        return JSON3.write(obj.data, allow_inf=true)
    else
        return JSON3.write(obj.data, allow_inf=true)
    end
end

function to_jsonld(obj; options::ConversionOptions=ConversionOptions())::String
    T = typeof(obj)
    mapping = get_type_mapping(T)

    # Build expanded JSON-LD
    result = Dict{String, Any}()

    # Add @type
    result["@type"] = [mapping.rdf_type.value]

    # Add @id if present
    if !isnothing(mapping.id_field)
        id_value = getfield(obj, mapping.id_field)
        if !isnothing(id_value)
            result["@id"] = string(id_value)
        end
    end

    # Add properties
    for (field_name, property_name) in mapping.field_mappings
        value = getfield(obj, field_name)

        if isnothing(value)
            continue  # Skip nothing values
        end

        # Expand property IRI
        property_iri = mapping.context isa Context ?
            expand_iri(property_name, mapping.context) : property_name

        # Convert value to JSON-LD format
        result[property_iri] = julia_value_to_jsonld(value)
    end

    # Optionally compact (would need compaction implementation)
    if options.compact && mapping.context isa Context
        # Add context
        result["@context"] = context_to_dict(mapping.context)
    end

    return JSON3.write(result, allow_inf=true)
end

"""
    julia_value_to_jsonld(value)

Convert a Julia value to JSON-LD representation.

# Arguments
- `value` - Julia value

# Returns
- JSON-LD value representation (array of value objects)
"""
function julia_value_to_jsonld(value)
    if value isa Vector
        return [julia_single_value_to_jsonld(v) for v in value]
    else
        return [julia_single_value_to_jsonld(value)]
    end
end

"""
    julia_single_value_to_jsonld(value)

Convert a single Julia value to JSON-LD value object.

# Arguments
- `value` - Single Julia value

# Returns
- JSON-LD value object
"""
function julia_single_value_to_jsonld(value)
    if value isa IRI
        return Dict("@id" => value.value)
    elseif value isa String
        return Dict("@value" => value)
    elseif value isa Int
        return Dict("@value" => value, "@type" => XSD.integer.value)
    elseif value isa Float64
        return Dict("@value" => value, "@type" => XSD.double.value)
    elseif value isa Bool
        return Dict("@value" => value, "@type" => XSD.boolean.value)
    else
        return Dict("@value" => string(value))
    end
end
