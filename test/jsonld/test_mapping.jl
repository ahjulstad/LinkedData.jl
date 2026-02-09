using Test
using LinkedData
using JSON3

@testset "JSON-LD Struct Mapping" begin

    @testset "Dynamic Parsing (JSONLDObject)" begin
        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@id": "http://example.org/alice",
          "@type": "Person",
          "name": "Alice",
          "age": 30,
          "email": "alice@example.org"
        }
        """

        obj = from_jsonld(json)

        @test obj isa JSONLDObject
        @test obj.id == "http://example.org/alice"
        @test "http://schema.org/Person" in obj.type
        @test obj.name == "Alice"
        @test obj.age == 30
        @test obj.email == "alice@example.org"
    end

    @testset "Dynamic Parsing - Missing Properties" begin
        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": "Person",
          "name": "Bob"
        }
        """

        obj = from_jsonld(json)

        @test obj.name == "Bob"
        @test isnothing(obj.age)
        @test isnothing(obj.email)
        @test isnothing(obj.id)
    end

    @testset "Dynamic Parsing - Multiple Types" begin
        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": ["Person", "Employee"],
          "name": "Charlie"
        }
        """

        obj = from_jsonld(json)

        @test length(obj.type) == 2
        @test "http://schema.org/Person" in obj.type
        @test "http://schema.org/Employee" in obj.type
    end

    @testset "Typed Parsing - Basic Struct" begin
        struct SimplePerson
            id::Union{String, Nothing}
            name::String
            age::Union{Int, Nothing}
        end

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": "SimplePerson",
          "@id": "http://example.org/david",
          "name": "David",
          "age": 25
        }
        """

        person = from_jsonld(SimplePerson, json)

        @test person isa SimplePerson
        @test person.id == "http://example.org/david"
        @test person.name == "David"
        @test person.age == 25
    end

    @testset "Typed Parsing - Optional Fields" begin
        struct PersonWithOptionals
            id::Union{String, Nothing}
            name::String
            age::Union{Int, Nothing}
            email::Union{String, Nothing}
        end

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": "PersonWithOptionals",
          "name": "Eve"
        }
        """

        person = from_jsonld(PersonWithOptionals, json)

        @test person.name == "Eve"
        @test isnothing(person.age)
        @test isnothing(person.email)
        @test isnothing(person.id)
    end

    @testset "Typed Parsing - snake_case to camelCase" begin
        struct PersonWithSnakeCase
            id::Union{String, Nothing}
            first_name::String
            last_name::String
            email_address::Union{String, Nothing}
        end

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": "PersonWithSnakeCase",
          "firstName": "Frank",
          "lastName": "Smith",
          "emailAddress": "frank@example.org"
        }
        """

        person = from_jsonld(PersonWithSnakeCase, json)

        @test person.first_name == "Frank"
        @test person.last_name == "Smith"
        @test person.email_address == "frank@example.org"
    end

    @testset "@jsonld Macro - Basic" begin
        @jsonld struct AnnotatedPerson
            id::Union{String, Nothing}
            name::String
            age::Union{Int, Nothing}
        end

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": "AnnotatedPerson",
          "name": "Grace",
          "age": 35
        }
        """

        person = from_jsonld(AnnotatedPerson, json)

        @test person.name == "Grace"
        @test person.age == 35

        # Verify it's in the registry
        @test haskey(LinkedData.TYPE_REGISTRY, AnnotatedPerson)
    end

    @testset "@jsonld Macro - Multiple Instances" begin
        @jsonld struct CachedPerson
            id::Union{String, Nothing}
            name::String
        end

        json1 = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": "CachedPerson",
          "name": "Henry"
        }
        """

        json2 = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": "CachedPerson",
          "name": "Iris"
        }
        """

        person1 = from_jsonld(CachedPerson, json1)
        person2 = from_jsonld(CachedPerson, json2)

        @test person1.name == "Henry"
        @test person2.name == "Iris"

        # Both should use the same cached mapping
        mapping = LinkedData.TYPE_REGISTRY[CachedPerson]
        @test mapping.julia_type == CachedPerson
    end

    @testset "Struct to JSON-LD" begin
        struct SerializablePerson
            id::Union{String, Nothing}
            name::String
            age::Union{Int, Nothing}
        end

        person = SerializablePerson("http://example.org/john", "John", 40)
        json = to_jsonld(person)

        # Parse back to verify
        parsed = JSON3.read(json)

        @test haskey(parsed, "@type")
        @test "http://schema.org/SerializablePerson" in parsed["@type"]
        @test parsed["@id"] == "http://example.org/john"

        # Name should be in expanded form
        name_iri = "http://schema.org/name"
        @test haskey(parsed, name_iri)
        @test length(parsed[name_iri]) == 1
        @test parsed[name_iri][1]["@value"] == "John"
    end

    @testset "Round-trip: Struct → JSON-LD → Struct" begin
        struct RoundTripPerson
            id::Union{String, Nothing}
            name::String
            age::Union{Int, Nothing}
        end

        original = RoundTripPerson("http://example.org/kate", "Kate", 28)
        json = to_jsonld(original)
        restored = from_jsonld(RoundTripPerson, json)

        @test restored.id == original.id
        @test restored.name == original.name
        @test restored.age == original.age
    end

    @testset "Type Inference" begin
        struct InferredType
            id::Union{String, Nothing}
            first_name::String
            user_age::Int
        end

        mapping = LinkedData.infer_type_mapping(InferredType)

        @test mapping.julia_type == InferredType
        @test mapping.rdf_type.value == "http://schema.org/InferredType"
        @test mapping.id_field == :id

        # Check field mappings (snake_case → camelCase)
        @test mapping.field_mappings[:first_name] == "firstName"
        @test mapping.field_mappings[:user_age] == "userAge"
    end

    @testset "Convention: to_camel_case" begin
        @test LinkedData.to_camel_case("name") == "name"
        @test LinkedData.to_camel_case("first_name") == "firstName"
        @test LinkedData.to_camel_case("user_email_address") == "userEmailAddress"
        @test LinkedData.to_camel_case("a_b_c") == "aBC"
    end

    @testset "Array Fields" begin
        struct PersonWithEmails
            id::Union{String, Nothing}
            name::String
            emails::Vector{String}
        end

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": "PersonWithEmails",
          "name": "Laura",
          "emails": ["laura1@example.org", "laura2@example.org"]
        }
        """

        person = from_jsonld(PersonWithEmails, json)

        @test person.name == "Laura"
        @test length(person.emails) == 2
        @test "laura1@example.org" in person.emails
        @test "laura2@example.org" in person.emails
    end

    @testset "JSONLDObject Display" begin
        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@id": "http://example.org/mike",
          "@type": "Person",
          "name": "Mike"
        }
        """

        obj = from_jsonld(json)
        str = sprint(show, obj)

        @test occursin("JSONLDObject", str)
        @test occursin("@id", str)
        @test occursin("@type", str)
    end

end
