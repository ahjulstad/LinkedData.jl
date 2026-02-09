@testset "SHACL Validation" begin
    @testset "Cardinality Constraints" begin
        @testset "MinCount" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            name_pred = IRI("http://xmlns.com/foaf/0.1/name")

            # Alice has no name - should violate minCount 1
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(name_pred,
                                            constraints=[MinCount(1)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms
            @test length(report.results) == 1

            # Add name - should pass
            add!(store, person, name_pred, Literal("Alice"))

            report = validate(store, [shape])
            @test report.conforms
            @test length(report.results) == 0
        end

        @testset "MaxCount" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            name_pred = IRI("http://xmlns.com/foaf/0.1/name")

            # Add two names
            add!(store, person, name_pred, Literal("Alice"))
            add!(store, person, name_pred, Literal("Alicia"))

            # maxCount 1 should fail
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(name_pred,
                                            constraints=[MaxCount(1)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms
            @test length(report.results) == 1
        end
    end

    @testset "Value Type Constraints" begin
        @testset "Datatype" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            age_pred = IRI("http://xmlns.com/foaf/0.1/age")

            # Age without datatype
            add!(store, person, age_pred, Literal("30"))

            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(age_pred,
                                            constraints=[Datatype(XSD.integer)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms

            # Fix: add age with correct datatype
            remove!(store, Triple(person, age_pred, Literal("30")))
            add!(store, person, age_pred, Literal("30", XSD.integer))

            report = validate(store, [shape])
            @test report.conforms
        end

        @testset "Class" begin
            store = RDFStore()
            alice = IRI("http://example.org/alice")
            bob = IRI("http://example.org/bob")
            knows = IRI("http://xmlns.com/foaf/0.1/knows")
            person_class = IRI("http://xmlns.com/foaf/0.1/Person")

            add!(store, alice, knows, bob)
            # Bob is not typed as Person yet

            shape = NodeShape(IRI("http://example.org/KnowsShape"),
                            targets=[TargetNode(alice)],
                            property_shapes=[
                                PropertyShape(knows,
                                            constraints=[Class(person_class)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms

            # Add type to Bob
            add!(store, bob, RDF.type_, person_class)

            report = validate(store, [shape])
            @test report.conforms
        end

        @testset "NodeKind" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            name_pred = IRI("http://xmlns.com/foaf/0.1/name")

            # Name is a literal - should pass NodeKind Literal
            add!(store, person, name_pred, Literal("Alice"))

            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(name_pred,
                                            constraints=[NodeKind(:Literal)])
                            ])

            report = validate(store, [shape])
            @test report.conforms

            # Should fail for IRI node kind
            shape2 = NodeShape(IRI("http://example.org/PersonShape2"),
                             targets=[TargetNode(person)],
                             property_shapes=[
                                 PropertyShape(name_pred,
                                             constraints=[NodeKind(:IRI)])
                             ])

            report = validate(store, [shape2])
            @test !report.conforms
        end
    end

    @testset "String Constraints" begin
        @testset "MinLength / MaxLength" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            name_pred = IRI("http://xmlns.com/foaf/0.1/name")

            add!(store, person, name_pred, Literal("Al"))

            # minLength 3 should fail
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(name_pred,
                                            constraints=[MinLength(3)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms

            # maxLength 1 should fail
            shape2 = NodeShape(IRI("http://example.org/PersonShape2"),
                             targets=[TargetNode(person)],
                             property_shapes=[
                                 PropertyShape(name_pred,
                                             constraints=[MaxLength(1)])
                             ])

            report = validate(store, [shape2])
            @test !report.conforms

            # maxLength 2 should pass
            shape3 = NodeShape(IRI("http://example.org/PersonShape3"),
                             targets=[TargetNode(person)],
                             property_shapes=[
                                 PropertyShape(name_pred,
                                             constraints=[MaxLength(2)])
                             ])

            report = validate(store, [shape3])
            @test report.conforms
        end

        @testset "Pattern" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            email_pred = IRI("http://xmlns.com/foaf/0.1/mbox")

            add!(store, person, email_pred, Literal("alice@example.org"))

            # Email pattern (using raw string for regex)
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(email_pred,
                                            constraints=[Pattern(raw"^[a-z]+@[a-z]+\.[a-z]+$")])
                            ])

            report = validate(store, [shape])
            @test report.conforms

            # Invalid email
            add!(store, person, email_pred, Literal("not-an-email"))

            report = validate(store, [shape])
            @test !report.conforms
        end

        @testset "HasValue" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            type_pred = RDF.type_
            person_class = IRI("http://xmlns.com/foaf/0.1/Person")

            # Alice not typed yet
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(type_pred,
                                            constraints=[HasValue(person_class)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms

            # Add type
            add!(store, person, type_pred, person_class)

            report = validate(store, [shape])
            @test report.conforms
        end

        @testset "In" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            status_pred = IRI("http://example.org/status")

            add!(store, person, status_pred, Literal("active"))

            # Valid values
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(status_pred,
                                            constraints=[In([Literal("active"), Literal("inactive")])])
                            ])

            report = validate(store, [shape])
            @test report.conforms

            # Invalid value
            remove!(store, Triple(person, status_pred, Literal("active")))
            add!(store, person, status_pred, Literal("deleted"))

            report = validate(store, [shape])
            @test !report.conforms
        end
    end

    @testset "Numeric Constraints" begin
        @testset "MinInclusive / MaxInclusive" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            age_pred = IRI("http://xmlns.com/foaf/0.1/age")

            add!(store, person, age_pred, Literal("30", XSD.integer))

            # Age >= 18
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(age_pred,
                                            constraints=[MinInclusive(18)])
                            ])

            report = validate(store, [shape])
            @test report.conforms

            # Age <= 25 should fail
            shape2 = NodeShape(IRI("http://example.org/PersonShape2"),
                             targets=[TargetNode(person)],
                             property_shapes=[
                                 PropertyShape(age_pred,
                                             constraints=[MaxInclusive(25)])
                             ])

            report = validate(store, [shape2])
            @test !report.conforms
        end

        @testset "MinExclusive / MaxExclusive" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            score_pred = IRI("http://example.org/score")

            add!(store, person, score_pred, Literal("50", XSD.integer))

            # Score > 40
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(score_pred,
                                            constraints=[MinExclusive(40)])
                            ])

            report = validate(store, [shape])
            @test report.conforms

            # Score < 50 should fail (50 is not < 50)
            shape2 = NodeShape(IRI("http://example.org/PersonShape2"),
                             targets=[TargetNode(person)],
                             property_shapes=[
                                 PropertyShape(score_pred,
                                             constraints=[MaxExclusive(50)])
                             ])

            report = validate(store, [shape2])
            @test !report.conforms
        end
    end

    @testset "Property Pair Constraints" begin
        @testset "Equals" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            name1 = IRI("http://example.org/name1")
            name2 = IRI("http://example.org/name2")

            add!(store, person, name1, Literal("Alice"))
            add!(store, person, name2, Literal("Alice"))

            # name1 equals name2 - should pass
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(name1,
                                            constraints=[Equals(name2)])
                            ])

            report = validate(store, [shape])
            @test report.conforms

            # Change name2 - should fail
            remove!(store, Triple(person, name2, Literal("Alice")))
            add!(store, person, name2, Literal("Alicia"))

            report = validate(store, [shape])
            @test !report.conforms
        end

        @testset "Disjoint" begin
            store = RDFStore()
            person = IRI("http://example.org/alice")
            friends = IRI("http://example.org/friends")
            enemies = IRI("http://example.org/enemies")
            bob = IRI("http://example.org/bob")

            add!(store, person, friends, bob)
            add!(store, person, enemies, bob)

            # friends and enemies should be disjoint - should fail
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetNode(person)],
                            property_shapes=[
                                PropertyShape(friends,
                                            constraints=[Disjoint(enemies)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms
        end
    end

    @testset "Target Types" begin
        @testset "TargetClass" begin
            store = RDFStore()
            alice = IRI("http://example.org/alice")
            bob = IRI("http://example.org/bob")
            charlie = IRI("http://example.org/charlie")
            person_class = IRI("http://xmlns.com/foaf/0.1/Person")
            name_pred = IRI("http://xmlns.com/foaf/0.1/name")

            # Type alice and bob as Person
            add!(store, alice, RDF.type_, person_class)
            add!(store, bob, RDF.type_, person_class)

            # Only alice has a name
            add!(store, alice, name_pred, Literal("Alice"))

            # Shape targets all Persons, requires name
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetClass(person_class)],
                            property_shapes=[
                                PropertyShape(name_pred,
                                            constraints=[MinCount(1)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms
            @test length(report.results) == 1  # Bob violates

            # Charlie is not a Person, so not validated
            @test !any(r -> r.focus_node == charlie, report.results)
        end

        @testset "TargetSubjectsOf" begin
            store = RDFStore()
            alice = IRI("http://example.org/alice")
            bob = IRI("http://example.org/bob")
            knows = IRI("http://xmlns.com/foaf/0.1/knows")
            name_pred = IRI("http://xmlns.com/foaf/0.1/name")

            # Alice knows Bob
            add!(store, alice, knows, bob)
            # Alice has no name

            # Target all subjects of "knows"
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetSubjectsOf(knows)],
                            property_shapes=[
                                PropertyShape(name_pred,
                                            constraints=[MinCount(1)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms
            @test length(report.results) == 1
            @test report.results[1].focus_node == alice
        end

        @testset "TargetObjectsOf" begin
            store = RDFStore()
            alice = IRI("http://example.org/alice")
            bob = IRI("http://example.org/bob")
            knows = IRI("http://xmlns.com/foaf/0.1/knows")
            name_pred = IRI("http://xmlns.com/foaf/0.1/name")

            # Alice knows Bob
            add!(store, alice, knows, bob)
            # Bob has no name

            # Target all objects of "knows"
            shape = NodeShape(IRI("http://example.org/PersonShape"),
                            targets=[TargetObjectsOf(knows)],
                            property_shapes=[
                                PropertyShape(name_pred,
                                            constraints=[MinCount(1)])
                            ])

            report = validate(store, [shape])
            @test !report.conforms
            @test length(report.results) == 1
            @test report.results[1].focus_node == bob
        end
    end

    @testset "Severity Levels" begin
        store = RDFStore()
        person = IRI("http://example.org/alice")
        name_pred = IRI("http://xmlns.com/foaf/0.1/name")

        # Warning severity - should not fail conforms
        shape = NodeShape(IRI("http://example.org/PersonShape"),
                        targets=[TargetNode(person)],
                        property_shapes=[
                            PropertyShape(name_pred,
                                        constraints=[MinCount(1)],
                                        severity=:Warning)
                        ])

        report = validate(store, [shape])
        @test report.conforms  # Warnings don't fail conformance
        @test length(report.results) == 1
        @test report.results[1].severity == :Warning
    end

    @testset "Custom Messages" begin
        store = RDFStore()
        person = IRI("http://example.org/alice")
        name_pred = IRI("http://xmlns.com/foaf/0.1/name")

        shape = NodeShape(IRI("http://example.org/PersonShape"),
                        targets=[TargetNode(person)],
                        property_shapes=[
                            PropertyShape(name_pred,
                                        constraints=[MinCount(1)],
                                        message="Every person must have a name!")
                        ])

        report = validate(store, [shape])
        @test !report.conforms
        @test length(report.results) == 1
        @test report.results[1].message == "Every person must have a name!"
    end

    @testset "Multiple Constraints" begin
        store = RDFStore()
        person = IRI("http://example.org/alice")
        age_pred = IRI("http://xmlns.com/foaf/0.1/age")

        # Age must be integer between 18 and 100
        add!(store, person, age_pred, Literal("30", XSD.integer))

        shape = NodeShape(IRI("http://example.org/PersonShape"),
                        targets=[TargetNode(person)],
                        property_shapes=[
                            PropertyShape(age_pred,
                                        constraints=[
                                            MinCount(1),
                                            MaxCount(1),
                                            Datatype(XSD.integer),
                                            MinInclusive(18),
                                            MaxInclusive(100)
                                        ])
                        ])

        report = validate(store, [shape])
        @test report.conforms

        # Age too young
        remove!(store, Triple(person, age_pred, Literal("30", XSD.integer)))
        add!(store, person, age_pred, Literal("10", XSD.integer))

        report = validate(store, [shape])
        @test !report.conforms
    end
end
