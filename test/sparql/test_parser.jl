@testset "SPARQL Parser" begin
    @testset "Basic SELECT Query" begin
        query_str = """
        SELECT ?person ?name
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/name> ?name .
        }
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test query.variables == [:person, :name]
        @test length(query.where_clause) == 1
        @test query.where_clause[1] isa TriplePattern

        pattern = query.where_clause[1]
        @test pattern.subject == :person
        @test pattern.predicate == IRI("http://xmlns.com/foaf/0.1/name")
        @test pattern.object == :name
    end

    @testset "SELECT with Multiple Patterns" begin
        query_str = """
        SELECT ?person ?friend
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/knows> ?friend .
            ?friend <http://xmlns.com/foaf/0.1/name> "Bob" .
        }
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test length(query.where_clause) == 2

        @test query.where_clause[1].subject == :person
        @test query.where_clause[1].predicate == IRI("http://xmlns.com/foaf/0.1/knows")
        @test query.where_clause[1].object == :friend

        @test query.where_clause[2].subject == :friend
        @test query.where_clause[2].predicate == IRI("http://xmlns.com/foaf/0.1/name")
        @test query.where_clause[2].object == Literal("Bob")
    end

    @testset "SELECT with PREFIX" begin
        query_str = """
        PREFIX foaf: <http://xmlns.com/foaf/0.1/>
        SELECT ?person ?name
        WHERE {
            ?person foaf:name ?name .
        }
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test length(query.where_clause) == 1

        pattern = query.where_clause[1]
        @test pattern.predicate == IRI("http://xmlns.com/foaf/0.1/name")
    end

    @testset "SELECT with 'a' shorthand" begin
        query_str = """
        SELECT ?person
        WHERE {
            ?person a <http://xmlns.com/foaf/0.1/Person> .
        }
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test length(query.where_clause) == 1

        pattern = query.where_clause[1]
        @test pattern.subject == :person
        @test pattern.predicate == RDF.type_
        @test pattern.object == IRI("http://xmlns.com/foaf/0.1/Person")
    end

    @testset "SELECT DISTINCT" begin
        query_str = """
        SELECT DISTINCT ?person
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/knows> ?friend .
        }
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test query.distinct == true
    end

    @testset "SELECT with LIMIT" begin
        query_str = """
        SELECT ?person
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/name> ?name .
        }
        LIMIT 10
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test query.modifiers.limit == 10
    end

    @testset "SELECT with OFFSET" begin
        query_str = """
        SELECT ?person
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/name> ?name .
        }
        OFFSET 5
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test query.modifiers.offset == 5
    end

    @testset "SELECT with LIMIT and OFFSET" begin
        query_str = """
        SELECT ?person
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/name> ?name .
        }
        LIMIT 10
        OFFSET 5
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test query.modifiers.limit == 10
        @test query.modifiers.offset == 5
    end

    @testset "SELECT with ORDER BY" begin
        query_str = """
        SELECT ?person ?name
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/name> ?name .
        }
        ORDER BY ?name
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test length(query.modifiers.order_by) == 1
        @test query.modifiers.order_by[1] == (:name, :asc)
    end

    @testset "SELECT with ORDER BY DESC" begin
        query_str = """
        SELECT ?person ?age
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/age> ?age .
        }
        ORDER BY ?age DESC
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test length(query.modifiers.order_by) == 1
        @test query.modifiers.order_by[1] == (:age, :desc)
    end

    @testset "SELECT with FILTER - Equality" begin
        query_str = """
        SELECT ?person
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/name> ?name .
            FILTER (?name = "Alice")
        }
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test length(query.where_clause) == 2

        filter_pattern = query.where_clause[2]
        @test filter_pattern isa FilterPattern

        expr = filter_pattern.expression
        @test expr isa ComparisonExpr
        @test expr.operator == :eq
        @test expr.left isa VarExpr
        @test expr.left.name == :name
        @test expr.right isa LiteralExpr
    end

    @testset "SELECT with FILTER - Comparison" begin
        query_str = """
        SELECT ?person
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/age> ?age .
            FILTER (?age > 30)
        }
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        filter_pattern = query.where_clause[2]
        @test filter_pattern isa FilterPattern

        expr = filter_pattern.expression
        @test expr isa ComparisonExpr
        @test expr.operator == :gt
    end

    @testset "SELECT with OPTIONAL" begin
        query_str = """
        SELECT ?person ?age
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/name> ?name .
            OPTIONAL {
                ?person <http://xmlns.com/foaf/0.1/age> ?age .
            }
        }
        """

        query = parse_sparql(query_str)

        @test query isa SelectQuery
        @test length(query.where_clause) == 2

        optional_pattern = query.where_clause[2]
        @test optional_pattern isa OptionalPattern
        @test length(optional_pattern.patterns) == 1
    end

    @testset "CONSTRUCT Query" begin
        query_str = """
        CONSTRUCT {
            ?person <http://xmlns.com/foaf/0.1/knows> ?friend .
        }
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/knows> ?friend .
        }
        """

        query = parse_sparql(query_str)

        @test query isa ConstructQuery
        @test length(query.template) == 1
        @test length(query.where_clause) == 1

        @test query.template[1].subject == :person
        @test query.template[1].predicate == IRI("http://xmlns.com/foaf/0.1/knows")
        @test query.template[1].object == :friend
    end

    @testset "ASK Query" begin
        query_str = """
        ASK {
            <http://example.org/alice> <http://xmlns.com/foaf/0.1/knows> <http://example.org/bob> .
        }
        """

        query = parse_sparql(query_str)

        @test query isa AskQuery
        @test length(query.where_clause) == 1
    end

    @testset "DESCRIBE Query" begin
        query_str = """
        DESCRIBE <http://example.org/alice>
        """

        query = parse_sparql(query_str)

        @test query isa DescribeQuery
        @test length(query.resources) == 1
        @test query.resources[1] == IRI("http://example.org/alice")
        @test isnothing(query.where_clause)
    end

    @testset "DESCRIBE Query with Variable" begin
        query_str = """
        DESCRIBE ?person
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/name> "Alice" .
        }
        """

        query = parse_sparql(query_str)

        @test query isa DescribeQuery
        @test length(query.resources) == 1
        @test query.resources[1] == :person
        @test !isnothing(query.where_clause)
        @test length(query.where_clause) == 1
    end

    @testset "Integration - Parse and Execute" begin
        # Setup test data
        store = RDFStore()

        alice = IRI("http://example.org/alice")
        bob = IRI("http://example.org/bob")
        name_pred = IRI("http://xmlns.com/foaf/0.1/name")
        age_pred = IRI("http://xmlns.com/foaf/0.1/age")

        add!(store, alice, name_pred, Literal("Alice"))
        add!(store, alice, age_pred, Literal("30", XSD.integer))
        add!(store, bob, name_pred, Literal("Bob"))
        add!(store, bob, age_pred, Literal("25", XSD.integer))

        # Parse and execute query
        query_str = """
        SELECT ?person ?name
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/name> ?name .
        }
        """

        parsed_query = parse_sparql(query_str)
        result = LinkedData.query(store, parsed_query)

        @test length(result) == 2
        names = Set([b[:name].value for b in result.bindings])
        @test "Alice" in names
        @test "Bob" in names
    end

    @testset "Integration - Parse and Execute with FILTER" begin
        store = RDFStore()

        alice = IRI("http://example.org/alice")
        bob = IRI("http://example.org/bob")
        age_pred = IRI("http://xmlns.com/foaf/0.1/age")

        add!(store, alice, age_pred, Literal("30", XSD.integer))
        add!(store, bob, age_pred, Literal("25", XSD.integer))

        query_str = """
        SELECT ?person
        WHERE {
            ?person <http://xmlns.com/foaf/0.1/age> ?age .
            FILTER (?age > 28)
        }
        """

        parsed_query = parse_sparql(query_str)
        result = LinkedData.query(store, parsed_query)

        @test length(result) == 1
        @test result.bindings[1][:person] == alice
    end
end
