/// Result builder that lets ``Video``'s init accept a list of ``Clip``s with control flow
/// (`if`, `for`, `switch`). You generally don't reference this type directly — write
/// `Video { ... }` and the compiler invokes it for you.
@resultBuilder
public enum VideoBuilder {
    /// The empty composition — `Video { }`.
    ///
    /// Without this overload an empty block is ambiguous between the two variadic
    /// `buildBlock`s below, and `Video { }` does not compile. An empty timeline is
    /// a real state: a new project, or one whose last clip was just deleted.
    public static func buildBlock() -> [any Clip] {
        []
    }

    public static func buildBlock(_ components: any Clip...) -> [any Clip] {
        Array(components)
    }

    public static func buildOptional(_ component: [any Clip]?) -> [any Clip] {
        component ?? []
    }

    public static func buildEither(first component: [any Clip]) -> [any Clip] {
        component
    }

    public static func buildEither(second component: [any Clip]) -> [any Clip] {
        component
    }

    public static func buildArray(_ components: [[any Clip]]) -> [any Clip] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: any Clip) -> [any Clip] {
        [expression]
    }

    public static func buildBlock(_ components: [any Clip]...) -> [any Clip] {
        components.flatMap { $0 }
    }
}
