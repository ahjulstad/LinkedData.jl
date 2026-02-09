@testset "RDF Store" begin
    @testset "Store creation" begin
        store = RDFStore()
        @test count_triples(store) == 0
        @test count_subjects(store) == 0
        @test count_predicates(store) == 0
        @test count_objects(store) == 0
    end

    @testset "Adding triples" begin
        store = RDFStore()

        alice = IRI("http://example.org/alice")
        knows = IRI("http://example.org/knows")
        bob = IRI("http://example.org/bob")

        triple = Triple(alice, knows, bob)

        @testset "Add single triple" begin
            add!(store, triple)
            @test count_triples(store) == 1
            @test has_triple(store, triple)
        end

        @testset "Add with components" begin
            store2 = RDFStore()
            add!(store2, alice, knows, bob)
            @test count_triples(store2) == 1
            @test has_triple(store2, triple)
        end

        @testset "Duplicate addition" begin
            store3 = RDFStore()
            add!(store3, triple)
            add!(store3, triple)  # Add same triple again
            @test count_triples(store3) == 1  # Should still be 1
        end

        @testset "Add multiple triples" begin
            store4 = RDFStore()
            charlie = IRI("http://example.org/charlie")

            triples = [
                Triple(alice, knows, bob),
                Triple(alice, knows, charlie),
                Triple(bob, knows, charlie)
            ]

            add!(store4, triples)
            @test count_triples(store4) == 3
        end
    end

    @testset "Removing triples" begin
        store = RDFStore()

        alice = IRI("http://example.org/alice")
        knows = IRI("http://example.org/knows")
        bob = IRI("http://example.org/bob")

        triple = Triple(alice, knows, bob)

        add!(store, triple)
        @test has_triple(store, triple)

        remove!(store, triple)
        @test count_triples(store) == 0
        @test !has_triple(store, triple)

        # Removing non-existent triple should not error
        remove!(store, triple)
        @test count_triples(store) == 0
    end

    @testset "Querying triples" begin
        store = RDFStore()

        alice = IRI("http://example.org/alice")
        bob = IRI("http://example.org/bob")
        charlie = IRI("http://example.org/charlie")
        knows = IRI("http://example.org/knows")
        likes = IRI("http://example.org/likes")

        # Build a small knowledge graph
        add!(store, alice, knows, bob)
        add!(store, alice, knows, charlie)
        add!(store, alice, likes, bob)
        add!(store, bob, knows, charlie)

        @testset "Query all triples" begin
            results = triples(store)
            @test length(results) == 4
        end

        @testset "Query by subject" begin
            results = triples(store, subject=alice)
            @test length(results) == 3
            @test all(t -> t.subject == alice, results)
        end

        @testset "Query by predicate" begin
            results = triples(store, predicate=knows)
            @test length(results) == 3
            @test all(t -> t.predicate == knows, results)
        end

        @testset "Query by object" begin
            results = triples(store, object=bob)
            @test length(results) == 2
            @test all(t -> t.object == bob, results)
        end

        @testset "Query by subject and predicate" begin
            results = triples(store, subject=alice, predicate=knows)
            @test length(results) == 2
            @test all(t -> t.subject == alice && t.predicate == knows, results)
        end

        @testset "Query by predicate and object" begin
            results = triples(store, predicate=knows, object=charlie)
            @test length(results) == 2
            @test all(t -> t.predicate == knows && t.object == charlie, results)
        end

        @testset "Query by subject, predicate, and object" begin
            results = triples(store, subject=alice, predicate=knows, object=bob)
            @test length(results) == 1
            @test results[1] == Triple(alice, knows, bob)
        end

        @testset "Query with no matches" begin
            dave = IRI("http://example.org/dave")
            results = triples(store, subject=dave)
            @test length(results) == 0
        end
    end

    @testset "Statistics" begin
        store = RDFStore()

        alice = IRI("http://example.org/alice")
        bob = IRI("http://example.org/bob")
        charlie = IRI("http://example.org/charlie")
        knows = IRI("http://example.org/knows")
        likes = IRI("http://example.org/likes")

        add!(store, alice, knows, bob)
        add!(store, alice, knows, charlie)
        add!(store, bob, likes, charlie)

        @test count_triples(store) == 3
        @test count_subjects(store) == 2  # alice and bob
        @test count_predicates(store) == 2  # knows and likes
        @test count_objects(store) == 2  # bob and charlie

        @test get_predicate_count(store, knows) == 2
        @test get_predicate_count(store, likes) == 1
    end

    @testset "Namespace management" begin
        store = RDFStore()

        @testset "Register namespace" begin
            foaf_ns = IRI("http://xmlns.com/foaf/0.1/")
            register_namespace!(store, "foaf", foaf_ns)

            @test haskey(store.namespaces, "foaf")
            @test store.namespaces["foaf"] == foaf_ns
        end

        @testset "Expand prefixed name" begin
            foaf_ns = IRI("http://xmlns.com/foaf/0.1/")
            register_namespace!(store, "foaf", foaf_ns)

            expanded = expand(store, "foaf:knows")
            @test expanded == IRI("http://xmlns.com/foaf/0.1/knows")
        end

        @testset "Expand unknown prefix" begin
            @test_throws ArgumentError expand(store, "unknown:name")
        end

        @testset "Abbreviate IRI" begin
            foaf_ns = IRI("http://xmlns.com/foaf/0.1/")
            register_namespace!(store, "foaf", foaf_ns)

            iri = IRI("http://xmlns.com/foaf/0.1/knows")
            abbr = abbreviate(store, iri)
            @test abbr == "foaf:knows"
        end

        @testset "Abbreviate unknown IRI" begin
            iri = IRI("http://unknown.org/something")
            abbr = abbreviate(store, iri)
            @test abbr === nothing
        end
    end

    @testset "Complex scenarios" begin
        @testset "Blank nodes" begin
            store = RDFStore()

            alice = IRI("http://example.org/alice")
            knows = IRI("http://example.org/knows")
            bn1 = BlankNode("_:b1")
            bn2 = BlankNode("_:b2")

            add!(store, alice, knows, bn1)
            add!(store, bn1, knows, bn2)

            @test count_triples(store) == 2

            # Query for triples with blank node subject
            results = triples(store, subject=bn1)
            @test length(results) == 1
            @test results[1].object == bn2
        end

        @testset "Literals with different types" begin
            store = RDFStore()

            person = IRI("http://example.org/person")
            name = IRI("http://example.org/name")
            age = IRI("http://example.org/age")
            active = IRI("http://example.org/active")

            add!(store, person, name, Literal("Alice"))
            add!(store, person, age, Literal("30", XSD.integer))
            add!(store, person, active, Literal("true", XSD.boolean))

            @test count_triples(store) == 3

            results = triples(store, subject=person)
            @test length(results) == 3
        end

        @testset "Multiple predicates for same subject-object" begin
            store = RDFStore()

            alice = IRI("http://example.org/alice")
            bob = IRI("http://example.org/bob")
            knows = IRI("http://example.org/knows")
            likes = IRI("http://example.org/likes")
            trusts = IRI("http://example.org/trusts")

            add!(store, alice, knows, bob)
            add!(store, alice, likes, bob)
            add!(store, alice, trusts, bob)

            @test count_triples(store) == 3

            # All three predicates should be retrievable
            results = triples(store, subject=alice, object=bob)
            @test length(results) == 3
        end
    end

    @testset "Iterator interface" begin
        store = RDFStore()

        alice = IRI("http://example.org/alice")
        bob = IRI("http://example.org/bob")
        knows = IRI("http://example.org/knows")

        add!(store, alice, knows, bob)

        @test length(store) == 1

        # Test iteration
        count = 0
        for triple in store
            count += 1
            @test triple.subject == alice
            @test triple.predicate == knows
            @test triple.object == bob
        end
        @test count == 1
    end

    @testset "Bulk operations" begin
        @testset "Clear all triples" begin
            store = RDFStore()

            alice = IRI("http://example.org/alice")
            bob = IRI("http://example.org/bob")
            charlie = IRI("http://example.org/charlie")
            knows = IRI("http://example.org/knows")

            add!(store, alice, knows, bob)
            add!(store, alice, knows, charlie)
            add!(store, bob, knows, charlie)

            @test count_triples(store) == 3

            # Remove all triples
            for triple in collect(triples(store))
                remove!(store, triple)
            end

            @test count_triples(store) == 0
            @test count_subjects(store) == 0
            @test count_predicates(store) == 0
        end

        @testset "Bulk removal by pattern" begin
            store = RDFStore()

            alice = IRI("http://example.org/alice")
            bob = IRI("http://example.org/bob")
            charlie = IRI("http://example.org/charlie")
            knows = IRI("http://example.org/knows")
            likes = IRI("http://example.org/likes")

            add!(store, alice, knows, bob)
            add!(store, alice, knows, charlie)
            add!(store, alice, likes, bob)
            add!(store, bob, knows, charlie)

            @test count_triples(store) == 4

            # Remove all "knows" relationships
            knows_triples = collect(triples(store, predicate=knows))
            for triple in knows_triples
                remove!(store, triple)
            end

            @test count_triples(store) == 1
            @test triples(store)[1].predicate == likes
        end
    end

    @testset "Namespace edge cases" begin
        @testset "Empty prefix" begin
            store = RDFStore()
            base_ns = IRI("http://example.org/")
            register_namespace!(store, "", base_ns)

            expanded = expand(store, ":alice")
            @test expanded == IRI("http://example.org/alice")
        end

        @testset "Override namespace" begin
            store = RDFStore()
            old_ns = IRI("http://old.example.org/")
            new_ns = IRI("http://new.example.org/")

            register_namespace!(store, "ex", old_ns)
            register_namespace!(store, "ex", new_ns)

            expanded = expand(store, "ex:test")
            @test expanded == IRI("http://new.example.org/test")
        end

        @testset "Abbreviate with multiple matching namespaces" begin
            store = RDFStore()
            ns1 = IRI("http://example.org/")
            ns2 = IRI("http://example.org/vocab/")

            register_namespace!(store, "ex", ns1)
            register_namespace!(store, "vocab", ns2)

            # Should match the longer, more specific namespace
            iri = IRI("http://example.org/vocab/term")
            abbr = abbreviate(store, iri)
            @test abbr == "vocab:term"
        end
    end

    @testset "Edge cases for triple patterns" begin
        @testset "Empty store queries" begin
            store = RDFStore()
            alice = IRI("http://example.org/alice")
            knows = IRI("http://example.org/knows")

            @test length(triples(store)) == 0
            @test length(triples(store, subject=alice)) == 0
            @test length(triples(store, predicate=knows)) == 0
        end

        @testset "Store with single triple" begin
            store = RDFStore()
            alice = IRI("http://example.org/alice")
            knows = IRI("http://example.org/knows")
            bob = IRI("http://example.org/bob")

            add!(store, alice, knows, bob)

            # All patterns should return the same single triple
            @test length(triples(store)) == 1
            @test length(triples(store, subject=alice)) == 1
            @test length(triples(store, predicate=knows)) == 1
            @test length(triples(store, object=bob)) == 1
        end

        @testset "Literal comparison" begin
            store = RDFStore()
            person = IRI("http://example.org/person")
            age_pred = IRI("http://example.org/age")

            age1 = Literal("30", XSD.integer)
            age2 = Literal("30", XSD.integer)

            add!(store, person, age_pred, age1)

            # Should find triple with equivalent literal
            results = triples(store, object=age2)
            @test length(results) == 1
        end
    end
end
