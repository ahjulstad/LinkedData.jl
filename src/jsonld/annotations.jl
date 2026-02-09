# JSON-LD Struct Annotations

"""
    @jsonld struct MyType ... end

Mark a struct for optimized JSON-LD processing with automatic mapping.

This macro registers the struct in the TYPE_REGISTRY for efficient repeated parsing.
Without this macro, type mappings are inferred on first use and not cached.

# Usage

Basic usage with convention-based mapping:
```julia
@jsonld struct Person
    id::Union{String, Nothing}
    name::String
    age::Union{Int, Nothing}
end
```

The macro will:
- Infer field mappings using snake_case → camelCase convention
- Map `id` field to @id
- Generate RDF type IRI from struct name
- Cache the mapping for efficient reuse

# Advanced Features

You can customize the mapping by defining functions after the struct:

```julia
@jsonld struct Employee
    id::Union{String, Nothing}
    first_name::String
    employee_id::String
end

# Customize RDF type
LinkedData.rdf_type(::Type{Employee}) = IRI("http://example.org/Employee")

# Customize context
LinkedData.jsonld_context(::Type{Employee}) = Context(vocab=IRI("http://example.org/"))

# Customize field mapping
LinkedData.field_mapping(::Type{Employee}, ::Val{:employee_id}) = "employeeID"
```

# Example

```julia
@jsonld struct Person
    id::Union{String, Nothing}
    name::String
    email::Union{String, Nothing}
end

# Parse many objects efficiently
json1 = \"\"\"{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Person",
  "name": "Alice"
}\"\"\"

json2 = \"\"\"{
  "@context": {"@vocab": "http://schema.org/"},
  "@type": "Person",
  "name": "Bob"
}\"\"\"

alice = from_jsonld(Person, json1)  # Uses cached mapping
bob = from_jsonld(Person, json2)    # Reuses same mapping (fast!)
```
"""
macro jsonld(struct_expr)
    # Extract struct name and fields
    if struct_expr.head != :struct
        error("@jsonld can only be applied to struct definitions")
    end

    # The struct definition
    struct_def = struct_expr

    # Extract type name
    type_spec = struct_def.args[2]
    type_name = type_spec isa Symbol ? type_spec : type_spec.args[1]

    # Return quoted expression that:
    # 1. Defines the struct
    # 2. Registers it in TYPE_REGISTRY
    return quote
        # Define the struct
        $(esc(struct_def))

        # Register type mapping after struct is defined
        let T = $(esc(type_name))
            # Infer mapping
            mapping = LinkedData.infer_type_mapping(T)

            # Check for customizations
            if hasmethod(LinkedData.rdf_type, (Type{T},))
                mapping = TypeMapping(
                    T,
                    LinkedData.rdf_type(T),
                    mapping.context,
                    mapping.field_mappings,
                    mapping.id_field
                )
            end

            if hasmethod(LinkedData.jsonld_context, (Type{T},))
                mapping = TypeMapping(
                    T,
                    mapping.rdf_type,
                    LinkedData.jsonld_context(T),
                    mapping.field_mappings,
                    mapping.id_field
                )
            end

            # Apply field mapping customizations
            custom_mappings = copy(mapping.field_mappings)
            for field_name in fieldnames(T)
                val_type = Val{field_name}
                if hasmethod(LinkedData.field_mapping, (Type{T}, val_type))
                    custom_mappings[field_name] = LinkedData.field_mapping(T, val_type())
                end
            end

            if custom_mappings != mapping.field_mappings
                mapping = TypeMapping(
                    T,
                    mapping.rdf_type,
                    mapping.context,
                    custom_mappings,
                    mapping.id_field
                )
            end

            # Store in registry
            LinkedData.TYPE_REGISTRY[T] = mapping
        end

        $(esc(type_name))
    end
end

# Customization hooks (can be overridden by user)

"""
    rdf_type(::Type{T})::IRI

Override this to customize the RDF type IRI for a struct.

# Example
```julia
@jsonld struct Employee
    name::String
end

LinkedData.rdf_type(::Type{Employee}) = IRI("http://example.org/Employee")
```
"""
function rdf_type end

"""
    jsonld_context(::Type{T})::Context

Override this to customize the JSON-LD context for a struct.

# Example
```julia
@jsonld struct Employee
    name::String
end

LinkedData.jsonld_context(::Type{Employee}) = Context(vocab=IRI("http://example.org/"))
```
"""
function jsonld_context end

"""
    field_mapping(::Type{T}, ::Val{field_name})::String

Override this to customize the JSON-LD property name for a specific field.

# Example
```julia
@jsonld struct Employee
    employee_id::String
end

LinkedData.field_mapping(::Type{Employee}, ::Val{:employee_id}) = "employeeID"
```
"""
function field_mapping end
