# SM-0001: task-local metrics context

Enable runtime dimension injection and factory overrides through task-local context for metrics.

## Overview

- Proposal: SM-0001
- Author(s): [Vladimir Kukushkin](https://github.com/kukushechkin)
- Status: **Awaiting Review**
- Issue: [apple/swift-metrics#165](https://github.com/apple/swift-metrics/issues/165)
- Implementation:
  - [apple/swift-metrics#XXX](https://github.com/apple/swift-metrics/pull/XXX)
- Related links:
  - [Lightweight proposals process description](https://github.com/apple/swift-metrics/blob/main/Sources/CoreMetrics/Docs.docc/Proposals/Proposals.md)

### Introduction

Add task-local context for metrics through two independent mechanisms:

1. **Task-local factory** - affects metric **creation** (which backend to use).
2. **Task-local dimensions** - affects metric **operations** (which labels to attach).

These work in opposite ways and solve different problems.

### Key Semantic Difference

Task-local factory and dimensions have different lifecycles:

| Feature        | When Applied               | Primary Use Case                           |
|----------------|----------------------------|--------------------------------------------|
| **Factory**    | Metric **creation** time   | Testing isolation, metrics initialization  |
| **Dimensions** | Metric **operation** time  | Runtime context                            |

**Example:**

```swift
let counter = Metrics.with(factory: testFactory) {
    Counter(label: "requests")  // Uses testFactory (captured at creation)
}

Metrics.with(factory: otherFactory) {
    counter.increment()  // Still uses testFactory (NOT otherFactory)
}

Metrics.with(mergingDimensions: [("env", "prod")]) {
    counter.increment()  // Uses testFactory + dimensions from this scope
}
```

### Motivation

Modern server applications need to add contextual information to metrics based on execution context. Two
independent scenarios illustrate this need:

#### Problem 1: Testing isolation

Testing code that emits metrics requires bootstrapping a test factory globally, preventing
parallel test execution and polluting test state.

```swift
@Test
func testRequestHandling() {
    let testFactory = TestMetrics()
    MetricsSystem.bootstrap(testFactory)  // Affects global state
    handleRequest()
    let counter = testFactory.expectCounter("requests")
}
```

#### Problem 2: Reporting metrics with different context

Developers need to report the same metric across the codebase, requiring manual context
propagation and verbose metric object creation.

```swift
class MultiTenantService {
    func handleRequest(userId: String, operations: [String]) {
        // Need user-specific counter
        let userCounter = Counter(
            label: "requests",
            dimensions: [("user", userId)]
        )
        userCounter.increment()

        let tenantId = getTenantIdForUser(userId)

        for operation in operations {
            processOperation(userId, tenantId, operation)  // Context flows automatically through nested calls
        }
    }

    func processOperation(userId: String, tenantId: String, operation: String) {
        // Need tenant + user + operation
        let operationCounter = Counter(
            label: "operations",
            dimensions: [("tenant", tenantId), ("user", userId), ("operation", operation)]
        )

        doProcessing()
        operationCounter.increment()  // Dimensions: user=userId, tenant=tenantId, operation=operation
    }
}
```

### Proposed solution

Add `MetricsSystem.with()` methods (also available as `Metrics.with()` via typealias) that provide two independent
task-local contexts:

1. **`with(factory:)`** - sets factory used at **metric creation time**.
2. **`with(mergingDimensions:)`** - merges dimensions at **metric operation time**.

## Part 1: Task-Local Factory (Creation-Time)

Task-local factory is captured **when you create a metric**, and that factory is used for the metric's entire lifetime.

### Usage pattern: factory override for testing

Create metrics within a test factory scope:

```swift
@Test
func testRequestHandling() async {
    let testFactory = TestMetrics()
    let counter = await Metrics.with(factory: testFactory) {
        Counter(label: "requests")  // Uses testFactory
    }

    counter.increment()  // Still uses testFactory

    let retrievedCounter = try testFactory.expectCounter("requests")
    #expect(retrievedCounter.values == [1])
}
```

When creating a metric, the factory is chosen in this order:

1. **Explicit `factory` parameter** (if provided) - highest priority.
2. **Task-local factory** via `with(factory:)` (if present).
3. **Global factory** via `MetricsSystem.bootstrap()` - fallback.

The factory is stored in the metric and used for all future operations.

## Part 2: Task-Local Dimensions (Operation-Time)

Task-local dimensions are merged **when you call metric operations** (increment, record, and so on), not when creating
metrics.

### Usage pattern: dimension accumulation and context layering

Dimensions accumulate through nested calls, enabling composable context. The same metric can be used across
different contexts by layering dimensions:

```swift
class MultiTenantService {
    // Assuming the outer context called `Metrics.with(factory:)` to set up the factor context
    let requestCounter: Counter = Counter(label: "requests")
    let operationCounter: Counter = Counter(label: "operations")

    func handleRequest(userId: String, operations: [String]) {
        // First increment with user dimension
        Metrics.with(mergingDimensions: [("user", userId)]) {
            requestCounter.increment()  // Dimensions: user=userId

            let tenantId = getTenantIdForUser(userId)

            // Layer tenant dimension - automatically includes user dimension
            Metrics.with(mergingDimensions: [("tenant", tenantId)]) {
                for operation in operations {
                    processOperation(operation)  // Context flows automatically through nested calls
                }
            }
        }
    }

    func processOperation(operation: String) {
        Metrics.with(mergingDimensions: [("operation", operation)]) {
            doProcessing()  // Context flows automatically through nested calls
            operationCounter.increment()  // Dimensions: user=userId, tenant=tenantId, operation=operation
        }
    }
}
```

## Detailed design

### Public API additions

This proposal adds task-local context support through `MetricsSystem.with()` methods and a convenience typealias.

#### Core methods with optional parameters

```swift
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension MetricsSystem {
    /// Runs the given closure with optional factory and dimensions bound to the task-local context.
    ///
    /// The factory parameter affects metric **creation** within the closure - metrics created inside will use
    /// the specified factory. The factory is captured at creation time and used for the metric's lifetime.
    ///
    /// The mergingDimensions parameter affects metric **operations** within the closure - any metric operation
    /// (increment, record, and so on) will merge these dimensions with the metric's base dimensions.
    ///
    /// Both parameters are optional. Pass `nil` or omit to skip that behavior.
    ///
    /// ## Example: Factory only
    ///
    /// ```swift
    /// let counter = Metrics.with(factory: testFactory) {
    ///     Counter(label: "requests")  // Uses testFactory
    /// }
    /// counter.increment()  // Still uses testFactory
    /// ```
    ///
    /// ## Example: Dimensions only
    ///
    /// ```swift
    /// Metrics.with(mergingDimensions: [("env", "prod")]) {
    ///     counter.increment()  // Adds env=prod dimension
    /// }
    /// ```
    ///
    /// ## Example: Both factory and dimensions
    ///
    /// ```swift
    /// Metrics.with(factory: testFactory, mergingDimensions: [("env", "test")]) {
    ///     let counter = Counter(label: "req")  // Created with testFactory
    ///     counter.increment()  // Uses testFactory + env=test dimension
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - factory: Optional metrics factory to use for metric creation within the closure.
    ///   - mergingDimensions: Optional dimensions to merge with metric operations within the closure.
    ///   - operation: The closure to execute with the factory and dimensions bound.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<Result, Failure: Error>(
        factory: MetricsFactory? = nil,
        mergingDimensions: [(String, String)]? = nil,
        _ operation: () throws(Failure) -> Result
    ) rethrows -> Result

    /// Runs the given async closure with optional factory and dimensions bound to the task-local context.
    ///
    /// Async variant of `with(factory:mergingDimensions:_:)`. See that method for detailed documentation.
    ///
    /// - Parameters:
    ///   - factory: Optional metrics factory to use for metric creation within the closure.
    ///   - mergingDimensions: Optional dimensions to merge with metric operations within the closure.
    ///   - operation: The async closure to execute with the factory and dimensions bound.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<Result, Failure: Error>(
        factory: MetricsFactory? = nil,
        mergingDimensions: [(String, String)]? = nil,
        _ operation: () async throws(Failure) -> Result
    ) async rethrows -> Result
}
```

#### Convenience typealias

```swift
/// A shorter alias for `MetricsSystem` for more ergonomic API usage.
///
/// This typealias allows using `Metrics.with(...)` instead of `MetricsSystem.with(...)`:
///
/// ```swift
/// Metrics.with(factory: testFactory) {
///     Counter(label: "requests")
/// }
/// ```
public typealias Metrics = MetricsSystem
```

Both methods support optional parameters - users can pass factory, dimensions, or both. The typed `Failure` generic
enables precise error propagation without requiring explicit error type annotations at call sites.

### API stability

This is a purely additive change with no breaking impact.

**Platform requirements**: Task-local functionality requires macOS 10.15+, iOS 13.0+, watchOS 6.0+, tvOS 13.0+ due to
the use of `@TaskLocal` property wrappers.

**Existing metrics backend implementations**: backends continue to work unchanged. Backends without handler caching
work but may experience performance degradation when used with task-local dimensions. Update `MetricsFactory` protocol
documentation to specify the caching requirement as a best practice.

**Existing users of Metrics**: all existing `Counter`, `Timer`, `Gauge`, `Meter`, and `Recorder` APIs remain
unchanged. Code that creates and uses metrics without task-local context continues to work with zero impact.

Libraries can adopt task-local dimensions gradually:

```swift
// Old style - still works
let counter = Counter(label: "requests", dimensions: [("endpoint", "/users")])
counter.increment()

// New style with dimensions - opt-in
Metrics.with(mergingDimensions: [("userId", userId)]) {
    counter.increment()  // endpoint + userId dimensions
}

// New style with factory and dimensions - opt-in
let counter = Metrics.with(factory: customFactory) {
    Counter(label: "requests")
}
Metrics.with(mergingDimensions: [("endpoint", "/users")]) {
    counter.increment()  // Uses customFactory + structured dimensions
}
```

### Future directions

No future directions identified.

### Alternatives considered

#### Alternative 1: add dimensions parameter to metric operations

Add dimension parameters to all metric operation methods:

```swift
counter.increment(by: 1, dimensions: [("endpoint", "/users")])
timer.recordNanoseconds(duration, dimensions: [("endpoint", "/users")])
```

**Advantages**:

- Very explicit at call site.
- Follows established patterns in other languages and frameworks.
- No task-local state.
- Clear which dimensions apply to each operation.

**Disadvantages**:

- **Breaking change**: modifies all metric operation methods (`increment()`, `record()`, `recordNanoseconds()`).
- **OR – Backend adoption required**: all backend implementations must update their handler protocols (`CounterHandler`,
  `TimerHandler`, `RecorderHandler`, `MeterHandler`) to accept dimensions parameters.
- **OR — also implicitly requests a new handler from the backend inside**: on par with the proposed desing,
- Verbose: must pass dimensions to every operation, even when dimensions are identical across many operations.
- Poor composability: helper functions must pass dimensions through parameters.

**Decision**: rejected because this does not solve dimensions propagation verbosity.

#### Alternative 2: require dimensions at metric creation only

Support task-local dimensions only at metric creation time, not operation time.

**Advantages**:

- Simpler implementation.
- No performance overhead on metric operations.

**Disadvantages**:

- Does not solve the key use case of applying dimensions at runtime based on execution context.

**Decision**: rejected because operation-time dimension merging is the primary use case.
