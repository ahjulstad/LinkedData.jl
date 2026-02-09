@testset "SPARQL Executor" begin
    # Setup test data
    store = RDFStore()

    # Define some IRIs
    alice = IRI("http://example.org/alice")
    bob = IRI("http://example.org/bob")
    charlie = IRI("http://example.org/charlie")

    knows = IRI("http://xmlns.com/foaf/0.1/knows")
    name_pred = IRI("http://xmlns.com/foaf/0.1/name")
    age_pred = IRI("http://xmlns.com/foaf/0.1/age")
    person_type = IRI("http://xmlns.com/foaf/0.1/Person")
    rdf_type = RDF.type_

    # Add test data
    add!(store, alice, rdf_type, person_type)
    add!(store, alice, name_pred, Literal("Alice"))
    add!(store, alice, age_pred, Literal("30", XSD.integer))
    add!(store, alice, knows, bob)
    add!(store, alice, knows, charlie)

    add!(store, bob, rdf_type, person_type)
    add!(store, bob, name_pred, Literal("Bob"))
    add!(store, bob, age_pred, Literal("25", XSD.integer))
    add!(store, bob, knows, charlie)

    add!(store, charlie, rdf_type, person_type)
    add!(store, charlie, name_pred, Literal("Charlie"))
    add!(store, charlie, age_pred, Literal("35", XSD.integer))

    @testset "Basic Triple Pattern Matching" begin
        # Query: SELECT ?person WHERE { ?person a foaf:Person }
        query = SelectQuery(
            [:person],
            [TriplePattern(:person, rdf_type, person_type)]
        )

        result = SemanticWeb.query(store, query)

        @test length(result) == 3
        @test result.variables == [:person]

        persons = Set([binding[:person] for binding in result.bindings])
        @test alice in persons
        @test bob in persons
        @test charlie in persons
    end

    @testset "SELECT with Multiple Variables" begin
        # Query: SELECT ?person ?name WHERE { ?person foaf:name ?name }
        query = SelectQuery(
            [:person, :name],
            [TriplePattern(:person, name_pred, :name)]
        )

        result = SemanticWeb.query(store, query)

        @test length(result) == 3
        @test result.variables == [:person, :name]

        # Check that we got all three names
        names = Set([binding[:name].value for binding in result.bindings])
        @test "Alice" in names
        @test "Bob" in names
        @test "Charlie" in names
    end

    @testset "JOIN - Multiple Triple Patterns" begin
        # Query: SELECT ?person ?friend WHERE { ?person foaf:knows ?friend }
        query = SelectQuery(
            [:person, :friend],
            [TriplePattern(:person, knows, :friend)]
        )

        result = SemanticWeb.query(store, query)

        @test length(result) == 3  # alice->bob, alice->charlie, bob->charlie

        # Check specific relationships
        bindings = [(b[:person], b[:friend]) for b in result.bindings]
        @test (alice, bob) in bindings
        @test (alice, charlie) in bindings
        @test (bob, charlie) in bindings
    end

    @testset "JOIN with Shared Variables" begin
        # Query: SELECT ?person ?name WHERE {
        #   ?person foaf:knows ?friend .
        #   ?friend foaf:name ?name
        # }
        query = SelectQuery(
            [:person, :name],
            [
                TriplePattern(:person, knows, :friend),
                TriplePattern(:friend, name_pred, :name)
            ]
        )

        result = SemanticWeb.query(store, query)

        # alice knows bob and charlie, bob knows charlie
        @test length(result) == 3

        # Check that names are correct
        alice_bindings = filter(b -> b[:person] == alice, result.bindings)
        alice_friend_names = Set([b[:name].value for b in alice_bindings])
        @test "Bob" in alice_friend_names
        @test "Charlie" in alice_friend_names

        bob_bindings = filter(b -> b[:person] == bob, result.bindings)
        @test length(bob_bindings) == 1
        @test bob_bindings[1][:name].value == "Charlie"
    end

    @testset "CONSTRUCT Query" begin
        # Query: CONSTRUCT { ?person foaf:knows ?friend } WHERE {
        #   ?person foaf:knows ?friend
        # }
        template = [TriplePattern(:person, knows, :friend)]
        where_clause = [TriplePattern(:person, knows, :friend)]

        query = ConstructQuery(template, where_clause)
        result = SemanticWeb.query(store, query)

        @test result isa ConstructResult
        @test length(result) == 3

        # Check that triples are correct
        triples_set = Set(result.triples)
        @test Triple(alice, knows, bob) in triples_set
        @test Triple(alice, knows, charlie) in triples_set
        @test Triple(bob, knows, charlie) in triples_set
    end

    @testset "ASK Query" begin
        @testset "ASK - Pattern Exists" begin
            # Query: ASK { alice foaf:knows bob }
            query = AskQuery([TriplePattern(alice, knows, bob)])
            result = SemanticWeb.query(store, query)

            @test result isa AskResult
            @test result.result == true
        end

        @testset "ASK - Pattern Does Not Exist" begin
            # Query: ASK { bob foaf:knows alice }
            query = AskQuery([TriplePattern(bob, knows, alice)])
            result = SemanticWeb.query(store, query)

            @test result isa AskResult
            @test result.result == false
        end
    end

    @testset "DESCRIBE Query" begin
        @testset "DESCRIBE by IRI" begin
            query = DescribeQuery([alice], nothing)
            result = SemanticWeb.query(store, query)

            @test result isa DescribeResult
            # Should include all triples where alice is subject
            @test length(result) >= 5  # type, name, age, knows bob, knows charlie

            # Check some expected triples
            triples_set = Set(result.triples)
            @test Triple(alice, name_pred, Literal("Alice")) in triples_set
            @test Triple(alice, knows, bob) in triples_set
        end

        @testset "DESCRIBE with WHERE clause" begin
            # DESCRIBE ?person WHERE { ?person foaf:name "Bob" }
            where_clause = [TriplePattern(:person, name_pred, Literal("Bob"))]
            query = DescribeQuery([:person], where_clause)
            result = SemanticWeb.query(store, query)

            @test result isa DescribeResult
            # Should describe Bob
            triples_set = Set(result.triples)
            @test Triple(bob, name_pred, Literal("Bob")) in triples_set
            @test Triple(bob, knows, charlie) in triples_set
        end
    end

    @testset "Query Modifiers" begin
        @testset "LIMIT" begin
            query = SelectQuery(
                [:person],
                [TriplePattern(:person, rdf_type, person_type)],
                QueryModifiers(limit=2)
            )

            result = SemanticWeb.query(store, query)
            @test length(result) == 2
        end

        @testset "OFFSET" begin
            query = SelectQuery(
                [:person],
                [TriplePattern(:person, rdf_type, person_type)],
                QueryModifiers(offset=1)
            )

            result = SemanticWeb.query(store, query)
            @test length(result) == 2  # 3 total - 1 offset
        end

        @testset "LIMIT and OFFSET" begin
            query = SelectQuery(
                [:person],
                [TriplePattern(:person, rdf_type, person_type)],
                QueryModifiers(limit=1, offset=1)
            )

            result = SemanticWeb.query(store, query)
            @test length(result) == 1
        end

        @testset "DISTINCT" begin
            # Add duplicate relationship
            add!(store, alice, knows, bob)  # Already exists

            query = SelectQuery(
                [:person, :friend],
                [TriplePattern(:person, knows, :friend)],
                QueryModifiers(),
                true  # distinct
            )

            result = SemanticWeb.query(store, query)
            # Should still be 3 unique relationships
            @test length(result) == 3
        end
    end

    @testset "FILTER Expressions" begin
        @testset "FILTER Comparison - Equality" begin
            # SELECT ?person WHERE { ?person foaf:name ?name FILTER(?name = "Bob") }
            query = SelectQuery(
                [:person],
                [
                    TriplePattern(:person, name_pred, :name),
                    FilterPattern(
                        ComparisonExpr(:eq, VarExpr(:name), LiteralExpr(Literal("Bob")))
                    )
                ]
            )

            result = SemanticWeb.query(store, query)
            @test length(result) == 1
            @test result.bindings[1][:person] == bob
        end

        @testset "FILTER Comparison - Numeric" begin
            # SELECT ?person WHERE { ?person foaf:age ?age FILTER(?age > 28) }
            query = SelectQuery(
                [:person],
                [
                    TriplePattern(:person, age_pred, :age),
                    FilterPattern(
                        ComparisonExpr(:gt, VarExpr(:age), LiteralExpr(Literal("28", XSD.integer)))
                    )
                ]
            )

            result = SemanticWeb.query(store, query)
            @test length(result) == 2  # Alice (30) and Charlie (35)

            persons = Set([b[:person] for b in result.bindings])
            @test alice in persons
            @test charlie in persons
            @test !(bob in persons)
        end

        @testset "FILTER Logical - AND" begin
            # SELECT ?person WHERE {
            #   ?person foaf:age ?age
            #   FILTER(?age > 20 && ?age < 32)
            # }
            query = SelectQuery(
                [:person],
                [
                    TriplePattern(:person, age_pred, :age),
                    FilterPattern(
                        LogicalExpr(:and, [
                            ComparisonExpr(:gt, VarExpr(:age), LiteralExpr(Literal("20", XSD.integer))),
                            ComparisonExpr(:lt, VarExpr(:age), LiteralExpr(Literal("32", XSD.integer)))
                        ])
                    )
                ]
            )

            result = SemanticWeb.query(store, query)
            @test length(result) == 2  # Bob (25) and Alice (30)

            persons = Set([b[:person] for b in result.bindings])
            @test alice in persons
            @test bob in persons
            @test !(charlie in persons)
        end

        @testset "FILTER Function - bound()" begin
            # Will test with OPTIONAL later
            query = SelectQuery(
                [:person, :name],
                [
                    TriplePattern(:person, rdf_type, person_type),
                    TriplePattern(:person, name_pred, :name),
                    FilterPattern(
                        FunctionExpr(:bound, [VarExpr(:name)])
                    )
                ]
            )

            result = SemanticWeb.query(store, query)
            @test length(result) == 3  # All persons have names
        end
    end

    @testset "OPTIONAL Patterns" begin
        # Add data where some people have age, some don't
        store2 = RDFStore()
        dave = IRI("http://example.org/dave")

        add!(store2, alice, name_pred, Literal("Alice"))
        add!(store2, alice, age_pred, Literal("30", XSD.integer))
        add!(store2, bob, name_pred, Literal("Bob"))
        # Bob has no age
        add!(store2, dave, name_pred, Literal("Dave"))
        # Dave has no age

        # SELECT ?person ?name ?age WHERE {
        #   ?person foaf:name ?name
        #   OPTIONAL { ?person foaf:age ?age }
        # }
        query = SelectQuery(
            [:person, :name, :age],
            [
                TriplePattern(:person, name_pred, :name),
                OptionalPattern([TriplePattern(:person, age_pred, :age)])
            ]
        )

        result = SemanticWeb.query(store2, query)

        @test length(result) == 3

        # Alice should have age
        alice_binding = filter(b -> b[:person] == alice, result.bindings)[1]
        @test haskey(alice_binding, :age)
        @test alice_binding[:age] == Literal("30", XSD.integer)

        # Bob should not have age
        bob_binding = filter(b -> b[:person] == bob, result.bindings)[1]
        @test !haskey(bob_binding, :age)

        # Dave should not have age
        dave_binding = filter(b -> b[:person] == dave, result.bindings)[1]
        @test !haskey(dave_binding, :age)
    end

    @testset "UNION Patterns" begin
        # SELECT ?person WHERE {
        #   { ?person foaf:name "Alice" } UNION { ?person foaf:name "Bob" }
        # }
        query = SelectQuery(
            [:person],
            [
                UnionPattern(
                    [TriplePattern(:person, name_pred, Literal("Alice"))],
                    [TriplePattern(:person, name_pred, Literal("Bob"))]
                )
            ]
        )

        result = SemanticWeb.query(store, query)

        @test length(result) == 2
        persons = Set([b[:person] for b in result.bindings])
        @test alice in persons
        @test bob in persons
        @test !(charlie in persons)
    end

    @testset "Complex Query - Friends of Friends" begin
        # SELECT ?person ?fof WHERE {
        #   ?person foaf:knows ?friend .
        #   ?friend foaf:knows ?fof .
        #   FILTER(?person != ?fof)
        # }
        query = SelectQuery(
            [:person, :fof],
            [
                TriplePattern(:person, knows, :friend),
                TriplePattern(:friend, knows, :fof),
                FilterPattern(
                    ComparisonExpr(:ne, VarExpr(:person), VarExpr(:fof))
                )
            ]
        )

        result = SemanticWeb.query(store, query)

        # alice->bob->charlie (alice knows charlie via bob)
        # alice->charlie->? (charlie knows nobody, so no results)
        # bob->charlie->? (charlie knows nobody, so no results)
        @test length(result) == 1
        @test result.bindings[1][:person] == alice
        @test result.bindings[1][:fof] == charlie
    end

    @testset "Empty Results" begin
        query = SelectQuery(
            [:x],
            [TriplePattern(:x, IRI("http://example.org/nonexistent"), :y)]
        )

        result = SemanticWeb.query(store, query)
        @test length(result) == 0
        @test isempty(result.bindings)
    end

    @testset "Iterator Interface" begin
        query = SelectQuery(
            [:person],
            [TriplePattern(:person, rdf_type, person_type)]
        )

        result = SemanticWeb.query(store, query)

        # Test iteration
        count = 0
        for binding in result
            count += 1
            @test haskey(binding, :person)
        end
        @test count == 3

        # Test indexing
        @test result[1] isa Dict{Symbol, RDFNode}
        @test length(result) == 3
    end

    @testset "Type invariance - concrete pattern vectors" begin
        # All query constructors should accept Vector{TriplePattern} (not just Vector{GraphPattern})
        tp = TriplePattern(:s, :p, :o)

        @testset "SelectQuery" begin
            q = SelectQuery([:s], [tp])
            @test q isa SelectQuery
            @test q.where_clause isa Vector{GraphPattern}
        end

        @testset "ConstructQuery" begin
            q = ConstructQuery([tp], [tp])
            @test q isa ConstructQuery
            @test q.where_clause isa Vector{GraphPattern}
        end

        @testset "AskQuery" begin
            q = AskQuery([tp])
            @test q isa AskQuery
            @test q.where_clause isa Vector{GraphPattern}
        end

        @testset "DescribeQuery" begin
            q = DescribeQuery([alice], [tp])
            @test q isa DescribeQuery
            @test q.resources isa Vector{Union{Symbol, RDFNode}}

            # Also accepts symbols
            q2 = DescribeQuery([:person])
            @test q2 isa DescribeQuery
        end

        @testset "OptionalPattern" begin
            p = OptionalPattern([tp])
            @test p isa OptionalPattern
            @test p.patterns isa Vector{GraphPattern}
        end

        @testset "UnionPattern" begin
            p = UnionPattern([tp], [tp])
            @test p isa UnionPattern
        end

        @testset "GroupPattern" begin
            p = GroupPattern([tp])
            @test p isa GroupPattern
            @test p.patterns isa Vector{GraphPattern}
        end

        @testset "Mixed pattern vectors" begin
            opt = OptionalPattern([tp])
            filter = FilterPattern(ComparisonExpr(:gt, VarExpr(:age), LiteralExpr(Literal("30", XSD.integer))))
            q = SelectQuery([:s], GraphPattern[tp, opt, filter])
            @test length(q.where_clause) == 3
        end
    end
end
