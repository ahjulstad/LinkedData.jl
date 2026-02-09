@testset "RDF Serialization" begin
    @testset "Parse string - Turtle" begin
        store = RDFStore()

        turtle_data = """
        @prefix ex: <http://example.org/> .
        @prefix foaf: <http://xmlns.com/foaf/0.1/> .

        ex:alice a foaf:Person ;
            foaf:name "Alice" ;
            foaf:age "30"^^<http://www.w3.org/2001/XMLSchema#integer> .
        """

        parse_string!(store, turtle_data, format=:turtle)

        @test count_triples(store) == 3

        # Check that namespaces were registered
        @test haskey(store.namespaces, "ex")
        @test haskey(store.namespaces, "foaf")

        # Check specific triples exist
        alice = IRI("http://example.org/alice")
        @test length(triples(store, subject=alice)) == 3
    end

    @testset "Parse string - N-Triples" begin
        store = RDFStore()

        nt_data = """
        <http://example.org/alice> <http://xmlns.com/foaf/0.1/name> "Alice" .
        <http://example.org/alice> <http://xmlns.com/foaf/0.1/knows> <http://example.org/bob> .
        <http://example.org/bob> <http://xmlns.com/foaf/0.1/name> "Bob" .
        """

        parse_string!(store, nt_data, format=:ntriples)

        @test count_triples(store) == 3

        alice = IRI("http://example.org/alice")
        bob = IRI("http://example.org/bob")

        @test length(triples(store, subject=alice)) == 2
        @test length(triples(store, subject=bob)) == 1
    end

    @testset "Load from file - Turtle" begin
        store = RDFStore()

        fixture_path = joinpath(@__DIR__, "..", "fixtures", "sample_data.ttl")
        load!(store, fixture_path)

        @test count_triples(store) > 0

        # Check for expected entities
        alice = IRI("http://example.org/alice")
        bob = IRI("http://example.org/bob")
        charlie = IRI("http://example.org/charlie")

        @test length(triples(store, subject=alice)) > 0
        @test length(triples(store, subject=bob)) > 0
        @test length(triples(store, subject=charlie)) > 0
    end

    @testset "Load from file - N-Triples" begin
        store = RDFStore()

        fixture_path = joinpath(@__DIR__, "..", "fixtures", "sample_data.nt")
        load!(store, fixture_path)

        @test count_triples(store) == 6

        alice = IRI("http://example.org/alice")
        @test length(triples(store, subject=alice)) == 4
    end

    @testset "Format auto-detection" begin
        @testset "Turtle file" begin
            store = RDFStore()
            fixture_path = joinpath(@__DIR__, "..", "fixtures", "sample_data.ttl")
            load!(store, fixture_path, format=:auto)
            @test count_triples(store) > 0
        end

        @testset "N-Triples file" begin
            store = RDFStore()
            fixture_path = joinpath(@__DIR__, "..", "fixtures", "sample_data.nt")
            load!(store, fixture_path, format=:auto)
            @test count_triples(store) == 6
        end
    end

    @testset "Save to file" begin
        # Create store with data
        store = RDFStore()

        alice = IRI("http://example.org/alice")
        bob = IRI("http://example.org/bob")
        knows = IRI("http://xmlns.com/foaf/0.1/knows")
        name_pred = IRI("http://xmlns.com/foaf/0.1/name")

        register_namespace!(store, "ex", IRI("http://example.org/"))
        register_namespace!(store, "foaf", IRI("http://xmlns.com/foaf/0.1/"))

        add!(store, alice, name_pred, Literal("Alice"))
        add!(store, alice, knows, bob)
        add!(store, bob, name_pred, Literal("Bob"))

        # Save to temporary file
        temp_file = tempname() * ".ttl"

        try
            save(store, temp_file, format=:turtle)
            @test isfile(temp_file)

            # Load back and verify
            store2 = RDFStore()
            load!(store2, temp_file)

            @test count_triples(store2) == count_triples(store)
            @test has_triple(store2, Triple(alice, knows, bob))
        finally
            # Cleanup
            if isfile(temp_file)
                rm(temp_file)
            end
        end
    end

    @testset "Round-trip: Save and Load" begin
        original = RDFStore()

        # Create complex data with different literal types
        person = IRI("http://example.org/person1")
        register_namespace!(original, "ex", IRI("http://example.org/"))

        add!(original, person, IRI("http://example.org/name"), Literal("Alice"))
        add!(original, person, IRI("http://example.org/age"), Literal("30", XSD.integer))
        add!(original, person, IRI("http://example.org/height"), Literal("1.75", XSD.double))
        add!(original, person, IRI("http://example.org/active"), Literal("true", XSD.boolean))
        add!(original, person, IRI("http://example.org/nickname"), Literal("Ali", lang="en"))

        temp_file = tempname() * ".ttl"

        try
            # Save and reload
            save(original, temp_file, format=:turtle)

            loaded = RDFStore()
            load!(loaded, temp_file)

            # Verify all triples survived the round trip
            @test count_triples(loaded) == count_triples(original)

            # Check each triple individually
            for triple in triples(original)
                @test has_triple(loaded, triple)
            end
        finally
            if isfile(temp_file)
                rm(temp_file)
            end
        end
    end

    @testset "Language-tagged literals" begin
        store = RDFStore()

        turtle_data = """
        @prefix ex: <http://example.org/> .

        ex:doc ex:title "Hello"@en ;
               ex:title "Hola"@es ;
               ex:title "Bonjour"@fr .
        """

        parse_string!(store, turtle_data, format=:turtle)

        @test count_triples(store) == 3

        doc = IRI("http://example.org/doc")
        titles = triples(store, subject=doc)

        @test length(titles) == 3

        # Check language tags
        langs = Set{Union{String, Nothing}}()
        for triple in titles
            if triple.object isa Literal
                push!(langs, triple.object.language)
            end
        end

        @test "en" in langs
        @test "es" in langs
        @test "fr" in langs
    end

    @testset "Blank nodes" begin
        store = RDFStore()

        turtle_data = """
        @prefix ex: <http://example.org/> .

        ex:alice ex:knows _:someone .
        _:someone ex:name "Anonymous" .
        """

        parse_string!(store, turtle_data, format=:turtle)

        @test count_triples(store) == 2

        # There should be triples with blank node subjects or objects
        all_triples = triples(store)
        has_blank = any(t -> t.subject isa BlankNode || t.object isa BlankNode, all_triples)
        @test has_blank
    end

    @testset "Error handling" begin
        @testset "Invalid file path" begin
            store = RDFStore()
            @test_throws ArgumentError load!(store, "/nonexistent/file.ttl")
        end

        @testset "Invalid format" begin
            store = RDFStore()
            @test_throws ArgumentError parse_string!(store, "", format=:invalid_format)
        end

        @testset "Malformed Turtle" begin
            store = RDFStore()
            bad_turtle = "This is not valid Turtle syntax @#&%"
            @test_throws ErrorException parse_string!(store, bad_turtle, format=:turtle)
        end
    end

    @testset "Typed literal round-trip" begin
        store = RDFStore()
        person = IRI("http://example.org/p1")
        register_namespace!(store, "ex", IRI("http://example.org/"))

        add!(store, person, IRI("http://example.org/int"), Literal("42", XSD.integer))
        add!(store, person, IRI("http://example.org/dbl"), Literal("3.14", XSD.double))
        add!(store, person, IRI("http://example.org/bool"), Literal("true", XSD.boolean))

        temp = tempname() * ".ttl"
        try
            save(store, temp, format=:turtle)

            loaded = RDFStore()
            load!(loaded, temp)

            @test count_triples(loaded) == 3
            for triple in triples(store)
                @test has_triple(loaded, triple)
            end
        finally
            isfile(temp) && rm(temp)
        end
    end

    @testset "N-Triples round-trip" begin
        store = RDFStore()
        s = IRI("http://example.org/s")

        add!(store, s, IRI("http://example.org/p1"), Literal("hello"))
        add!(store, s, IRI("http://example.org/p2"), Literal("42", XSD.integer))
        add!(store, s, IRI("http://example.org/p3"), Literal("hola", lang="es"))
        add!(store, s, IRI("http://example.org/p4"), IRI("http://example.org/o"))

        temp = tempname() * ".nt"
        try
            save(store, temp, format=:ntriples)

            loaded = RDFStore()
            load!(loaded, temp, format=:ntriples)

            @test count_triples(loaded) == count_triples(store)
            for triple in triples(store)
                @test has_triple(loaded, triple)
            end
        finally
            isfile(temp) && rm(temp)
        end
    end

    @testset "Blank node parsing" begin
        store = RDFStore()
        nt_data = """
        _:b1 <http://example.org/name> "Node1" .
        <http://example.org/s> <http://example.org/ref> _:b1 .
        """

        parse_string!(store, nt_data, format=:ntriples)
        @test count_triples(store) == 2

        # Verify blank nodes were parsed correctly
        all = triples(store)
        has_blank_subject = any(t -> t.subject isa BlankNode, all)
        has_blank_object = any(t -> t.object isa BlankNode, all)
        @test has_blank_subject
        @test has_blank_object
    end
end
