using Test
using LinkedData
using JSON3

@testset "JSON-LD Integration" begin

    @testset "Parse Simple JSON-LD" begin
        store = RDFStore()

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@id": "http://example.org/alice",
          "@type": "Person",
          "name": "Alice"
        }
        """

        jsonld_to_triples!(store, json)

        @test length(store) == 2  # rdf:type + name
        @test has_triple(store, Triple(
            IRI("http://example.org/alice"),
            RDF.type_,
            IRI("http://schema.org/Person")
        ))
        @test has_triple(store, Triple(
            IRI("http://example.org/alice"),
            IRI("http://schema.org/name"),
            Literal("Alice")
        ))
    end

    @testset "Parse JSON-LD with Multiple Properties" begin
        store = RDFStore()

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@id": "http://example.org/alice",
          "@type": "Person",
          "name": "Alice",
          "email": "alice@example.org",
          "age": 30
        }
        """

        jsonld_to_triples!(store, json)

        @test length(store) == 4  # rdf:type + name + email + age

        # Check all triples exist
        alice = IRI("http://example.org/alice")
        @test has_triple(store, Triple(alice, RDF.type_, IRI("http://schema.org/Person")))
        @test has_triple(store, Triple(alice, IRI("http://schema.org/name"), Literal("Alice")))
        @test has_triple(store, Triple(alice, IRI("http://schema.org/email"), Literal("alice@example.org")))
        @test has_triple(store, Triple(alice, IRI("http://schema.org/age"), Literal("30")))
    end

    @testset "Parse JSON-LD without @id (Blank Node)" begin
        store = RDFStore()

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@type": "Person",
          "name": "Anonymous"
        }
        """

        jsonld_to_triples!(store, json)

        @test length(store) == 2  # rdf:type + name

        # Find the blank node subject
        all_triples = collect(store)
        @test any(t -> t.subject isa BlankNode, all_triples)
    end

    @testset "Parse JSON-LD with Blank Node @id" begin
        store = RDFStore()

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@id": "_:person1",
          "@type": "Person",
          "name": "Someone"
        }
        """

        jsonld_to_triples!(store, json)

        @test length(store) == 2

        # Check blank node with specific ID
        person1 = BlankNode("person1")
        @test has_triple(store, Triple(person1, RDF.type_, IRI("http://schema.org/Person")))
        @test has_triple(store, Triple(person1, IRI("http://schema.org/name"), Literal("Someone")))
    end

    @testset "Parse JSON-LD with Array Values" begin
        store = RDFStore()

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@id": "http://example.org/alice",
          "@type": "Person",
          "name": "Alice",
          "email": ["alice@example.org", "alice@work.org"]
        }
        """

        jsonld_to_triples!(store, json)

        @test length(store) == 4  # rdf:type + name + email1 + email2

        alice = IRI("http://example.org/alice")
        @test has_triple(store, Triple(alice, IRI("http://schema.org/email"), Literal("alice@example.org")))
        @test has_triple(store, Triple(alice, IRI("http://schema.org/email"), Literal("alice@work.org")))
    end

    @testset "Parse JSON-LD with Prefix Notation" begin
        store = RDFStore()

        json = """
        {
          "@context": {
            "schema": "http://schema.org/",
            "ex": "http://example.org/"
          },
          "@id": "ex:alice",
          "@type": "schema:Person",
          "schema:name": "Alice"
        }
        """

        jsonld_to_triples!(store, json)

        @test length(store) == 2

        alice = IRI("http://example.org/alice")
        @test has_triple(store, Triple(alice, RDF.type_, IRI("http://schema.org/Person")))
        @test has_triple(store, Triple(alice, IRI("http://schema.org/name"), Literal("Alice")))
    end

    @testset "Parse JSON-LD with Multiple Types" begin
        store = RDFStore()

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@id": "http://example.org/alice",
          "@type": ["Person", "Employee"],
          "name": "Alice"
        }
        """

        jsonld_to_triples!(store, json)

        @test length(store) == 3  # 2x rdf:type + name

        alice = IRI("http://example.org/alice")
        @test has_triple(store, Triple(alice, RDF.type_, IRI("http://schema.org/Person")))
        @test has_triple(store, Triple(alice, RDF.type_, IRI("http://schema.org/Employee")))
    end

    @testset "Parse JSON-LD with @id References" begin
        store = RDFStore()

        json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@id": "http://example.org/alice",
          "@type": "Person",
          "name": "Alice",
          "knows": {"@id": "http://example.org/bob"}
        }
        """

        jsonld_to_triples!(store, json)

        @test length(store) == 3  # rdf:type + name + knows

        alice = IRI("http://example.org/alice")
        bob = IRI("http://example.org/bob")
        @test has_triple(store, Triple(alice, IRI("http://schema.org/knows"), bob))
    end

    @testset "Context Parsing" begin
        json = """
        {
          "@context": {
            "@vocab": "http://schema.org/",
            "name": "http://xmlns.com/foaf/0.1/name"
          },
          "name": "Test"
        }
        """

        ctx = parse_context(json)

        @test !isnothing(ctx.vocab)
        @test ctx.vocab.value == "http://schema.org/"
        @test haskey(ctx.terms, "name")
        @test ctx.terms["name"].iri == "http://xmlns.com/foaf/0.1/name"
    end

    @testset "Expand IRI" begin
        ctx = Context(vocab=IRI("http://schema.org/"))

        @test expand_iri("name", ctx) == "http://schema.org/name"
        @test expand_iri("http://example.org/full", ctx) == "http://example.org/full"
        @test expand_iri("@type", ctx) == "@type"
    end

    @testset "Expand IRI with Prefix" begin
        ctx = Context()
        ctx.prefixes["schema"] = "http://schema.org/"

        @test expand_iri("schema:Person", ctx) == "http://schema.org/Person"
        @test expand_iri("schema:name", ctx) == "http://schema.org/name"
    end

    @testset "Compact IRI" begin
        ctx = Context(vocab=IRI("http://schema.org/"))

        @test compact_iri("http://schema.org/name", ctx) == "name"
        @test compact_iri("http://example.org/other", ctx) == "http://example.org/other"
    end

    @testset "Compact IRI with Prefix" begin
        ctx = Context()
        ctx.prefixes["schema"] = "http://schema.org/"

        @test compact_iri("http://schema.org/Person", ctx) == "schema:Person"
        @test compact_iri("http://schema.org/name", ctx) == "schema:name"
    end

    @testset "Merge Contexts" begin
        ctx1 = Context(vocab=IRI("http://schema.org/"))
        ctx2 = Context(vocab=IRI("http://example.org/"))

        merged = merge_contexts(ctx1, ctx2)

        @test merged.vocab.value == "http://example.org/"  # ctx2 overrides
    end

    @testset "Triples to JSON-LD" begin
        store = RDFStore()
        alice = IRI("http://example.org/alice")

        add!(store, alice, RDF.type_, IRI("http://schema.org/Person"))
        add!(store, alice, IRI("http://schema.org/name"), Literal("Alice"))
        add!(store, alice, IRI("http://schema.org/age"), Literal("30"))

        json = triples_to_jsonld(store, subject=alice)

        # Parse back to verify
        parsed = JSON3.read(json)
        @test parsed["@id"] == "http://example.org/alice"
        @test "http://schema.org/Person" in parsed["@type"]
    end

    @testset "Triples to JSON-LD with Context" begin
        store = RDFStore()
        alice = IRI("http://example.org/alice")

        add!(store, alice, RDF.type_, IRI("http://schema.org/Person"))
        add!(store, alice, IRI("http://schema.org/name"), Literal("Alice"))

        ctx = Context(vocab=IRI("http://schema.org/"))
        json = triples_to_jsonld(store, context=ctx, subject=alice)

        parsed = JSON3.read(json)
        @test haskey(parsed, "@context")
        @test parsed["@context"]["@vocab"] == "http://schema.org/"
    end

    @testset "Round-trip: JSON-LD → Triples → JSON-LD" begin
        original_json = """
        {
          "@context": {"@vocab": "http://schema.org/"},
          "@id": "http://example.org/alice",
          "@type": "Person",
          "name": "Alice"
        }
        """

        # Parse to triples
        store = RDFStore()
        jsonld_to_triples!(store, original_json)

        # Convert back to JSON-LD
        ctx = Context(vocab=IRI("http://schema.org/"))
        result_json = triples_to_jsonld(store, context=ctx, subject=IRI("http://example.org/alice"))

        # Parse and verify
        parsed = JSON3.read(result_json)
        @test parsed["@id"] == "http://example.org/alice"
        @test "http://schema.org/Person" in parsed["@type"] || "Person" in parsed["@type"]
    end

end
