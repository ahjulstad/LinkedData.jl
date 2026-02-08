# Common RDF namespaces as constants

# ============================================================================
# RDF - Resource Description Framework
# ============================================================================

module RDF
    using ..SemanticWeb: IRI

    const type_ = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
    const Property = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#Property")
    const Statement = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#Statement")
    const subject = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#subject")
    const predicate = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#predicate")
    const object = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#object")
    const List = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#List")
    const nil = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")
    const first = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#first")
    const rest = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#rest")
    const value = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#value")
    const langString = IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#langString")

    const ns = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
end

# ============================================================================
# RDFS - RDF Schema
# ============================================================================

module RDFS
    using ..SemanticWeb: IRI

    const Resource = IRI("http://www.w3.org/2000/01/rdf-schema#Resource")
    const Class = IRI("http://www.w3.org/2000/01/rdf-schema#Class")
    const subClassOf = IRI("http://www.w3.org/2000/01/rdf-schema#subClassOf")
    const subPropertyOf = IRI("http://www.w3.org/2000/01/rdf-schema#subPropertyOf")
    const domain = IRI("http://www.w3.org/2000/01/rdf-schema#domain")
    const range = IRI("http://www.w3.org/2000/01/rdf-schema#range")
    const label = IRI("http://www.w3.org/2000/01/rdf-schema#label")
    const comment = IRI("http://www.w3.org/2000/01/rdf-schema#comment")
    const member = IRI("http://www.w3.org/2000/01/rdf-schema#member")
    const Container = IRI("http://www.w3.org/2000/01/rdf-schema#Container")
    const ContainerMembershipProperty = IRI("http://www.w3.org/2000/01/rdf-schema#ContainerMembershipProperty")
    const isDefinedBy = IRI("http://www.w3.org/2000/01/rdf-schema#isDefinedBy")
    const seeAlso = IRI("http://www.w3.org/2000/01/rdf-schema#seeAlso")
    const Literal = IRI("http://www.w3.org/2000/01/rdf-schema#Literal")
    const Datatype = IRI("http://www.w3.org/2000/01/rdf-schema#Datatype")

    const ns = "http://www.w3.org/2000/01/rdf-schema#"
end

# ============================================================================
# OWL - Web Ontology Language
# ============================================================================

module OWL
    using ..SemanticWeb: IRI

    const Thing = IRI("http://www.w3.org/2002/07/owl#Thing")
    const Nothing = IRI("http://www.w3.org/2002/07/owl#Nothing")
    const Class = IRI("http://www.w3.org/2002/07/owl#Class")
    const ObjectProperty = IRI("http://www.w3.org/2002/07/owl#ObjectProperty")
    const DatatypeProperty = IRI("http://www.w3.org/2002/07/owl#DatatypeProperty")
    const AnnotationProperty = IRI("http://www.w3.org/2002/07/owl#AnnotationProperty")
    const Ontology = IRI("http://www.w3.org/2002/07/owl#Ontology")
    const imports = IRI("http://www.w3.org/2002/07/owl#imports")
    const versionInfo = IRI("http://www.w3.org/2002/07/owl#versionInfo")
    const equivalentClass = IRI("http://www.w3.org/2002/07/owl#equivalentClass")
    const equivalentProperty = IRI("http://www.w3.org/2002/07/owl#equivalentProperty")
    const sameAs = IRI("http://www.w3.org/2002/07/owl#sameAs")
    const differentFrom = IRI("http://www.w3.org/2002/07/owl#differentFrom")
    const inverseOf = IRI("http://www.w3.org/2002/07/owl#inverseOf")
    const TransitiveProperty = IRI("http://www.w3.org/2002/07/owl#TransitiveProperty")
    const SymmetricProperty = IRI("http://www.w3.org/2002/07/owl#SymmetricProperty")
    const FunctionalProperty = IRI("http://www.w3.org/2002/07/owl#FunctionalProperty")
    const InverseFunctionalProperty = IRI("http://www.w3.org/2002/07/owl#InverseFunctionalProperty")

    const ns = "http://www.w3.org/2002/07/owl#"
end

# ============================================================================
# XSD - XML Schema Datatypes
# ============================================================================

module XSD
    using ..SemanticWeb: IRI

    const string = IRI("http://www.w3.org/2001/XMLSchema#string")
    const boolean = IRI("http://www.w3.org/2001/XMLSchema#boolean")
    const decimal = IRI("http://www.w3.org/2001/XMLSchema#decimal")
    const integer = IRI("http://www.w3.org/2001/XMLSchema#integer")
    const double = IRI("http://www.w3.org/2001/XMLSchema#double")
    const float = IRI("http://www.w3.org/2001/XMLSchema#float")
    const date = IRI("http://www.w3.org/2001/XMLSchema#date")
    const time = IRI("http://www.w3.org/2001/XMLSchema#time")
    const dateTime = IRI("http://www.w3.org/2001/XMLSchema#dateTime")
    const dateTimeStamp = IRI("http://www.w3.org/2001/XMLSchema#dateTimeStamp")
    const gYear = IRI("http://www.w3.org/2001/XMLSchema#gYear")
    const gMonth = IRI("http://www.w3.org/2001/XMLSchema#gMonth")
    const gDay = IRI("http://www.w3.org/2001/XMLSchema#gDay")
    const gYearMonth = IRI("http://www.w3.org/2001/XMLSchema#gYearMonth")
    const gMonthDay = IRI("http://www.w3.org/2001/XMLSchema#gMonthDay")
    const duration = IRI("http://www.w3.org/2001/XMLSchema#duration")
    const yearMonthDuration = IRI("http://www.w3.org/2001/XMLSchema#yearMonthDuration")
    const dayTimeDuration = IRI("http://www.w3.org/2001/XMLSchema#dayTimeDuration")
    const byte = IRI("http://www.w3.org/2001/XMLSchema#byte")
    const short = IRI("http://www.w3.org/2001/XMLSchema#short")
    const int = IRI("http://www.w3.org/2001/XMLSchema#int")
    const long = IRI("http://www.w3.org/2001/XMLSchema#long")
    const unsignedByte = IRI("http://www.w3.org/2001/XMLSchema#unsignedByte")
    const unsignedShort = IRI("http://www.w3.org/2001/XMLSchema#unsignedShort")
    const unsignedInt = IRI("http://www.w3.org/2001/XMLSchema#unsignedInt")
    const unsignedLong = IRI("http://www.w3.org/2001/XMLSchema#unsignedLong")
    const positiveInteger = IRI("http://www.w3.org/2001/XMLSchema#positiveInteger")
    const nonNegativeInteger = IRI("http://www.w3.org/2001/XMLSchema#nonNegativeInteger")
    const negativeInteger = IRI("http://www.w3.org/2001/XMLSchema#negativeInteger")
    const nonPositiveInteger = IRI("http://www.w3.org/2001/XMLSchema#nonPositiveInteger")
    const hexBinary = IRI("http://www.w3.org/2001/XMLSchema#hexBinary")
    const base64Binary = IRI("http://www.w3.org/2001/XMLSchema#base64Binary")
    const anyURI = IRI("http://www.w3.org/2001/XMLSchema#anyURI")
    const language = IRI("http://www.w3.org/2001/XMLSchema#language")
    const normalizedString = IRI("http://www.w3.org/2001/XMLSchema#normalizedString")
    const token = IRI("http://www.w3.org/2001/XMLSchema#token")
    const NMTOKEN = IRI("http://www.w3.org/2001/XMLSchema#NMTOKEN")
    const Name = IRI("http://www.w3.org/2001/XMLSchema#Name")
    const NCName = IRI("http://www.w3.org/2001/XMLSchema#NCName")

    const ns = "http://www.w3.org/2001/XMLSchema#"
end

# ============================================================================
# SHACL - Shapes Constraint Language
# ============================================================================

module SHACL
    using ..SemanticWeb: IRI

    # Core SHACL vocabulary
    const Shape = IRI("http://www.w3.org/ns/shacl#Shape")
    const NodeShape = IRI("http://www.w3.org/ns/shacl#NodeShape")
    const PropertyShape = IRI("http://www.w3.org/ns/shacl#PropertyShape")

    # Targets
    const targetClass = IRI("http://www.w3.org/ns/shacl#targetClass")
    const targetNode = IRI("http://www.w3.org/ns/shacl#targetNode")
    const targetObjectsOf = IRI("http://www.w3.org/ns/shacl#targetObjectsOf")
    const targetSubjectsOf = IRI("http://www.w3.org/ns/shacl#targetSubjectsOf")

    # Properties
    const path = IRI("http://www.w3.org/ns/shacl#path")
    const property = IRI("http://www.w3.org/ns/shacl#property")

    # Cardinality constraints
    const minCount = IRI("http://www.w3.org/ns/shacl#minCount")
    const maxCount = IRI("http://www.w3.org/ns/shacl#maxCount")

    # Value type constraints
    const class_ = IRI("http://www.w3.org/ns/shacl#class")
    const datatype = IRI("http://www.w3.org/ns/shacl#datatype")
    const nodeKind = IRI("http://www.w3.org/ns/shacl#nodeKind")

    # String constraints
    const minLength = IRI("http://www.w3.org/ns/shacl#minLength")
    const maxLength = IRI("http://www.w3.org/ns/shacl#maxLength")
    const pattern = IRI("http://www.w3.org/ns/shacl#pattern")
    const flags = IRI("http://www.w3.org/ns/shacl#flags")

    # Numeric constraints
    const minInclusive = IRI("http://www.w3.org/ns/shacl#minInclusive")
    const maxInclusive = IRI("http://www.w3.org/ns/shacl#maxInclusive")
    const minExclusive = IRI("http://www.w3.org/ns/shacl#minExclusive")
    const maxExclusive = IRI("http://www.w3.org/ns/shacl#maxExclusive")

    # Validation results
    const ValidationReport = IRI("http://www.w3.org/ns/shacl#ValidationReport")
    const ValidationResult = IRI("http://www.w3.org/ns/shacl#ValidationResult")
    const conforms = IRI("http://www.w3.org/ns/shacl#conforms")
    const result = IRI("http://www.w3.org/ns/shacl#result")
    const focusNode = IRI("http://www.w3.org/ns/shacl#focusNode")
    const resultPath = IRI("http://www.w3.org/ns/shacl#resultPath")
    const resultSeverity = IRI("http://www.w3.org/ns/shacl#resultSeverity")
    const resultMessage = IRI("http://www.w3.org/ns/shacl#resultMessage")
    const sourceConstraintComponent = IRI("http://www.w3.org/ns/shacl#sourceConstraintComponent")
    const sourceShape = IRI("http://www.w3.org/ns/shacl#sourceShape")
    const value = IRI("http://www.w3.org/ns/shacl#value")

    # Severity levels
    const Violation = IRI("http://www.w3.org/ns/shacl#Violation")
    const Warning = IRI("http://www.w3.org/ns/shacl#Warning")
    const Info = IRI("http://www.w3.org/ns/shacl#Info")

    const ns = "http://www.w3.org/ns/shacl#"
end
