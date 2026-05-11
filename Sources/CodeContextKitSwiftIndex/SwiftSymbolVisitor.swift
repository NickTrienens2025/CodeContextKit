import Foundation
import SwiftSyntax
import CodeContextKitCore

class SwiftSymbolVisitor: SyntaxVisitor {
    let filePath: String
    let locationConverter: SourceLocationConverter
    let content: String
    var symbols: [SymbolRecord] = []
    var references: [SymbolRecord.Reference] = []
    var typeStack: [String] = []
    var activeScope: String?
    let estimator = TokenEstimator()

    init(filePath: String, locationConverter: SourceLocationConverter, content: String) {
        self.filePath = filePath
        self.locationConverter = locationConverter
        self.content = content
        super.init(viewMode: .sourceAccurate)
    }

    private func currentEnclosingType() -> String? {
        typeStack.last
    }

    private func qualifiedName(for name: String) -> String {
        if typeStack.isEmpty {
            return name
        } else {
            return typeStack.joined(separator: ".") + "." + name
        }
    }

    private func addSymbol(
        kind: SymbolRecord.Kind,
        name: String,
        signature: String,
        node: some SyntaxProtocol,
        docComment: String? = nil,
        accessLevel: String? = nil
    ) {
        let startLoc = node.startLocation(converter: locationConverter)
        let endLoc = node.endLocation(converter: locationConverter)
        
        let symbol = SymbolRecord(
            kind: kind,
            name: name,
            qualifiedName: qualifiedName(for: name),
            signature: signature.trimmingCharacters(in: .whitespacesAndNewlines),
            filePath: filePath,
            startLine: startLoc.line,
            endLine: endLoc.line,
            enclosingType: currentEnclosingType(),
            accessLevel: accessLevel,
            docComment: docComment,
            estimatedTokens: estimator.estimate(node.description)
        )
        symbols.append(symbol)
    }

    private func addReference(name: String, node: some SyntaxProtocol) {
        let startLoc = node.startLocation(converter: locationConverter)
        let endLoc = node.endLocation(converter: locationConverter)
        
        references.append(SymbolRecord.Reference(
            name: name,
            startLine: startLoc.line,
            endLine: endLoc.line,
            context: activeScope
        ))
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let accessLevel = node.modifiers.first?.name.text
        addSymbol(kind: .struct, name: name, signature: "struct \(name)", node: node, accessLevel: accessLevel)
        typeStack.append(name)
        activeScope = qualifiedName(for: name)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
        activeScope = typeStack.last
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let accessLevel = node.modifiers.first?.name.text
        addSymbol(kind: .class, name: name, signature: "class \(name)", node: node, accessLevel: accessLevel)
        typeStack.append(name)
        activeScope = qualifiedName(for: name)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
        activeScope = typeStack.last
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let accessLevel = node.modifiers.first?.name.text
        addSymbol(kind: .actor, name: name, signature: "actor \(name)", node: node, accessLevel: accessLevel)
        typeStack.append(name)
        activeScope = qualifiedName(for: name)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
        activeScope = typeStack.last
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let accessLevel = node.modifiers.first?.name.text
        addSymbol(kind: .enum, name: name, signature: "enum \(name)", node: node, accessLevel: accessLevel)
        typeStack.append(name)
        activeScope = qualifiedName(for: name)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
        activeScope = typeStack.last
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let accessLevel = node.modifiers.first?.name.text
        addSymbol(kind: .protocol, name: name, signature: "protocol \(name)", node: node, accessLevel: accessLevel)
        typeStack.append(name)
        activeScope = qualifiedName(for: name)
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
        activeScope = typeStack.last
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.extendedType.trimmedDescription
        addSymbol(kind: .extension, name: name, signature: "extension \(name)", node: node)
        typeStack.append(name)
        activeScope = qualifiedName(for: name)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
        activeScope = typeStack.last
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let signature = node.funcKeyword.text + " " + name + node.signature.trimmedDescription
        let accessLevel = node.modifiers.first?.name.text
        
        var kind: SymbolRecord.Kind = .function
        if name.hasPrefix("test") && (currentEnclosingType()?.hasSuffix("Tests") == true || filePath.contains("Tests/")) {
            kind = .test
        }
        
        addSymbol(kind: kind, name: name, signature: signature, node: node, accessLevel: accessLevel)
        activeScope = qualifiedName(for: name)
        return .visitChildren
    }
    
    override func visitPost(_ node: FunctionDeclSyntax) {
        activeScope = typeStack.last
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = "init"
        let signature = "init" + node.signature.trimmedDescription
        let accessLevel = node.modifiers.first?.name.text
        addSymbol(kind: .initializer, name: name, signature: signature, node: node, accessLevel: accessLevel)
        activeScope = qualifiedName(for: name)
        return .visitChildren
    }
    
    override func visitPost(_ node: InitializerDeclSyntax) {
        activeScope = typeStack.last
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Only index as a property if the parent is a member block (type member)
        // Local variables inside functions/closures should be ignored
        var current: Syntax? = node.parent
        var isMember = false
        while let p = current {
            if p.is(MemberBlockItemListSyntax.self) {
                isMember = true
                break
            }
            if p.is(CodeBlockItemListSyntax.self) {
                // Inside a function body
                break
            }
            current = p.parent
        }
        
        if isMember {
            for binding in node.bindings {
                if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                    let accessLevel = node.modifiers.first?.name.text
                    let typeAnnotation = binding.typeAnnotation?.trimmedDescription ?? ""
                    addSymbol(kind: .property, name: name, signature: node.bindingSpecifier.text + " " + name + typeAnnotation, node: node, accessLevel: accessLevel)
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        addReference(name: node.baseName.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        addReference(name: node.declName.baseName.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        addReference(name: node.name.text, node: node)
        return .visitChildren
    }
}
