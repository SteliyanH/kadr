/// Result builder that lets ``Video``'s init accept a list of ``Clip``s with control flow
/// (`if`, `for`, `switch`). You generally don't reference this type directly — write
/// `Video { ... }` and the compiler invokes it for you.
@resultBuilder
public enum VideoBuilder {
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
