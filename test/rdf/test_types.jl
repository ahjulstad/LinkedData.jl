@testset "RDF Types" begin
    @testset "IRI" begin
        @testset "Construction" begin
            iri = IRI("http://example.org/resource")
            @test iri.value == "http://example.org/resource"
            @test string(iri) == "http://example.org/resource"
        end

        @testset "Validation" begin
            # IRIs cannot contain whitespace
            @test_throws ArgumentError IRI("http://example.org/bad resource")
        end

        @testset "Equality and hashing" begin
            iri1 = IRI("http://example.org/resource")
            iri2 = IRI("http://example.org/resource")
            iri3 = IRI("http://example.org/other")

            @test iri1 == iri2
            @test iri1 != iri3
            @test hash(iri1) == hash(iri2)
            @test hash(iri1) != hash(iri3)
        end

        @testset "Display" begin
            iri = IRI("http://example.org/resource")
            @test occursin("http://example.org/resource", string(iri))
        end
    end

    @testset "Literal" begin
        @testset "Plain literal" begin
            lit = Literal("hello")
            @test lit.value == "hello"
            @test lit.datatype === nothing
            @test lit.language === nothing
        end

        @testset "Typed literal" begin
            lit = Literal("42", XSD.integer)
            @test lit.value == "42"
            @test lit.datatype == XSD.integer
            @test lit.language === nothing
        end

        @testset "Language-tagged literal" begin
            lit = Literal("hello", lang="en")
            @test lit.value == "hello"
            @test lit.language == "en"
            @test lit.datatype === nothing

            # Language tags should be normalized to lowercase
            lit2 = Literal("hello", lang="EN")
            @test lit2.language == "en"
        end

        @testset "Validation" begin
            # Cannot have both datatype and language
            @test_throws ArgumentError Literal("hello", XSD.string, "en")
        end

        @testset "Equality" begin
            lit1 = Literal("hello", lang="en")
            lit2 = Literal("hello", lang="en")
            lit3 = Literal("hello", lang="fr")
            lit4 = Literal("hello", XSD.string)

            @test lit1 == lit2
            @test lit1 != lit3
            @test lit1 != lit4
        end
    end

    @testset "BlankNode" begin
        @testset "Named blank node" begin
            bn = BlankNode("_:b1")
            @test bn.id == "_:b1"
        end

        @testset "Anonymous blank node" begin
            bn1 = BlankNode()
            bn2 = BlankNode()
            @test bn1.id != bn2.id  # Different blank nodes
        end

        @testset "Equality" begin
            bn1 = BlankNode("_:b1")
            bn2 = BlankNode("_:b1")
            bn3 = BlankNode("_:b2")

            @test bn1 == bn2
            @test bn1 != bn3
        end
    end

    @testset "Triple" begin
        @testset "Construction" begin
            subject = IRI("http://example.org/subject")
            predicate = IRI("http://example.org/predicate")
            object = Literal("value")

            triple = Triple(subject, predicate, object)

            @test triple.subject == subject
            @test triple.predicate == predicate
            @test triple.object == object
        end

        @testset "With blank node subject" begin
            subject = BlankNode("_:b1")
            predicate = IRI("http://example.org/predicate")
            object = IRI("http://example.org/object")

            triple = Triple(subject, predicate, object)
            @test triple.subject == subject
        end

        @testset "Equality" begin
            s = IRI("http://example.org/s")
            p = IRI("http://example.org/p")
            o = Literal("value")

            triple1 = Triple(s, p, o)
            triple2 = Triple(s, p, o)
            triple3 = Triple(s, p, Literal("other"))

            @test triple1 == triple2
            @test triple1 != triple3
        end
    end

    @testset "Quad" begin
        @testset "Construction with graph" begin
            subject = IRI("http://example.org/subject")
            predicate = IRI("http://example.org/predicate")
            object = Literal("value")
            graph = IRI("http://example.org/graph")

            quad = Quad(subject, predicate, object, graph)

            @test quad.subject == subject
            @test quad.predicate == predicate
            @test quad.object == object
            @test quad.graph == graph
        end

        @testset "Construction without graph" begin
            subject = IRI("http://example.org/subject")
            predicate = IRI("http://example.org/predicate")
            object = Literal("value")

            quad = Quad(subject, predicate, object)
            @test quad.graph === nothing
        end

        @testset "From Triple" begin
            triple = Triple(
                IRI("http://example.org/s"),
                IRI("http://example.org/p"),
                Literal("o")
            )
            graph = IRI("http://example.org/graph")

            quad = Quad(triple, graph)
            @test quad.subject == triple.subject
            @test quad.predicate == triple.predicate
            @test quad.object == triple.object
            @test quad.graph == graph
        end
    end

    @testset "Namespaces" begin
        @testset "RDF namespace" begin
            @test RDF.type_.value == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
            @test RDF.Property.value == "http://www.w3.org/1999/02/22-rdf-syntax-ns#Property"
        end

        @testset "RDFS namespace" begin
            @test RDFS.Class.value == "http://www.w3.org/2000/01/rdf-schema#Class"
            @test RDFS.label.value == "http://www.w3.org/2000/01/rdf-schema#label"
        end

        @testset "XSD namespace" begin
            @test XSD.string.value == "http://www.w3.org/2001/XMLSchema#string"
            @test XSD.integer.value == "http://www.w3.org/2001/XMLSchema#integer"
            @test XSD.boolean.value == "http://www.w3.org/2001/XMLSchema#boolean"
        end

        @testset "OWL namespace" begin
            @test OWL.Class.value == "http://www.w3.org/2002/07/owl#Class"
            @test OWL.sameAs.value == "http://www.w3.org/2002/07/owl#sameAs"
        end

        @testset "SHACL namespace" begin
            @test SHACL.Shape.value == "http://www.w3.org/ns/shacl#Shape"
            @test SHACL.minCount.value == "http://www.w3.org/ns/shacl#minCount"
        end
    end
end
