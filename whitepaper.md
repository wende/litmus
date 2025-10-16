# Purity Analysis for Elixir: Theoretically Possible, Practically Challenging

**Implementing a purity analysis system for Elixir is theoretically possible but faces significant practical challenges.** While static analysis can identify obvious side effects and trace direct function calls, Elixir's dynamic nature—including metaprogramming, dynamic dispatch, NIFs, and process-based concurrency—creates fundamental obstacles that prevent complete compile-time purity verification. The most viable approach combines conservative static analysis on BEAM bytecode (similar to Erlang's PURITY tool), optional developer annotations, and convention-based practices, accepting that some pure functions will be misclassified and dynamic code paths will require runtime information.

**Why this matters:** Purity analysis could enable compiler optimizations, improve testability, support parallelization, and provide better documentation. However, any implementation must balance theoretical soundness with practical usability in a language designed for fault-tolerant, concurrent systems rather than mathematical purity.

**The reality check:** The Elixir/BEAM ecosystem currently has no mature purity analysis tools, reflecting both technical challenges and philosophical differences from purely functional languages like Haskell. While experimental attempts exist (like Efx for algebraic effects), they remain proof-of-concepts rather than production tools.

## Existing tools reveal a significant gap

The Elixir ecosystem lacks any production-ready purity analysis system. **Dialyzer**, the primary static analysis tool for BEAM languages, performs sophisticated type inference using "success typing" but has no concept of pure versus impure functions. It cannot distinguish between functions with side effects and those without, track I/O operations, or verify purity claims. Dialyzer's only purity-related feature is enforcing a small whitelist of known-pure functions in guard clauses—a hardcoded list rather than the result of purity analysis.

**Credo** and **Sobelow** focus on code quality and security respectively, with no purity tracking capabilities. The experimental **Efx project** (github.com/wende/efx) attempted to add first-class algebraic effects to Elixir with compile-time effect checking, but appears abandoned and couldn't handle effects passed through message passing—a fundamental BEAM limitation. A newer testing library also named Efx provides effect mocking for tests but performs no static purity analysis.

The closest existing tool is the **Erlang PURITY analyzer** developed by Pitidis and Sagonas in 2011. This tool performs static analysis on BEAM bytecode to classify functions into purity levels: referentially transparent, side-effect free, or side-effect free with dependencies. It successfully analyzed the entire Erlang/OTP distribution and was integrated into compiler development branches. However, it cannot analyze dynamically-called functions (using apply/3), requires conservative approximations, and has seen limited adoption. This tool demonstrates that bytecode-level purity analysis is viable for BEAM languages, providing a blueprint for Elixir implementation.

Elixir's recent gradual typing work (v1.18+) focuses on type correctness rather than effect tracking, though the infrastructure being built could potentially support effect annotations in the future. The community currently relies on testing practices, architectural patterns like "purity injection," and manual discipline to manage side effects.

## Technical implementation requires multi-phase analysis

Building a purity analysis system for Elixir demands combining AST traversal, call graph construction, and transitive closure computation. **Phase one involves direct effect detection** by parsing Elixir source into its Abstract Syntax Tree—three-element tuples of `{operation, metadata, arguments}`—and using `Macro.postwalk` or `Macro.prewalk` for depth-first traversal. The analyzer must pattern-match against known side-effecting operations including IO operations (File.*, IO.*, System.cmd), process operations (spawn, send, receive), ETS/DETS operations, side-effecting BIFs like :erlang.send, and GenServer/Agent calls.

For example, detecting IO operations:
```elixir
{_ast, side_effects} = Macro.postwalk(ast, [], fn
  {{:., _, [{:__aliases__, _, [:IO]}, function]}, _, _} = node, acc ->
    {node, [{:io, function} | acc]}
  node, acc -> {node, acc}
end)
```

**Phase two builds a call graph** to trace function invocations across the codebase. Erlang's built-in XREF (cross-reference tool) provides this capability using digraph representations with vertices for functions and edges for calls. It supports queries like "which functions call function X?" and can analyze entire applications. For runtime behavior, the ECG tool captures actual function calls using Erlang's trace mechanism, revealing dynamic dispatch patterns that static analysis misses.

Constructing call graphs in Elixir requires extracting function definitions from compiled modules, traversing their ASTs to identify callees, and building a directed graph where nodes represent `{module, function, arity}` tuples and edges represent call relationships. Recursive analysis then traces the transitive closure of function calls.

**Phase three performs transitive purity inference** through fixed-point iteration. Starting with functions that have direct side effects marked as impure, the algorithm propagates impurity backward through the call graph—any function calling an impure function becomes impure itself. This requires iterating until reaching a fixed point where no new functions are marked impure:

```elixir
def analyze(call_graph, direct_effects) do
  initial = Map.new(direct_effects, fn {func, effects} -> 
    {func, effects}
  end)
  fixed_point(call_graph, initial, %{})
end

defp fixed_point(graph, current, previous) do
  if current == previous do
    current  # Converged
  else
    next = propagate_effects(graph, current)
    fixed_point(graph, next, current)
  end
end
```

Academic research provides theoretical foundations through **type-and-effect systems**. Nielson and Nielson's framework extends regular types with effect annotations (τ₁ → ε τ₂), where ε represents a set of side effects. Modern effect systems like Koka use row-polymorphic effect types with flexible composition (`⟨exn,div|μ⟩`) and effect handlers for elimination. Algebraic effect handlers treat effects as resumable operations with handler-provided semantics, enabling user-definable control flow abstractions.

For dynamically-typed languages, **gradual effect systems** combine static and dynamic checking through unknown effects (⊤), allowing effect tracking without full static types. This approach lets developers progressively annotate codebases while maintaining backward compatibility—exactly what Elixir would need.

## BEAM characteristics create fundamental obstacles

Elixir's dynamic nature poses severe challenges for static purity analysis. **Dynamic dispatch** is pervasive: module names evaluated at runtime, `apply/3` enabling completely dynamic function invocation with all parameters determined at runtime, and private functions bypassed through dynamic calls. When code like `module_name.process(arg)` has `module_name` as a variable, static analysis cannot determine which function executes, breaking call graph construction and making whole-program analysis impossible.

Consider dependency injection patterns:
```elixir
defmodule Cache do
  def get(key, implementation \\ Cache.Memory) do
    implementation.fetch(key)  # Runtime dispatch
  end
end
```

Without runtime information, an analyzer cannot know if `get/2` is pure—it depends entirely on which implementation is provided.

**Metaprogramming and macros** execute at compile-time, transforming the AST before analysis can occur. Macros can inject arbitrary code including side effects, with no syntactic distinction between pure functions and macro calls. The `use` macro triggers `__using__` callbacks that inject code invisibly. Code generation can be conditional based on compile-time configuration, resulting in different expansions in different environments. For instance:

```elixir
defmodule Logger do
  defmacro log(message) do
    quote do
      IO.puts("#{DateTime.utc_now()}: #{unquote(message)}")
    end
  end
end

def process(x) do
  Logger.log("Processing")  # Expands to IO.puts
  x * 2  # Looks pure, actually does IO
end
```

Analyzers must work with post-macro-expansion AST, losing the original programmer intent and facing different code in different contexts.

**NIFs (Native Implemented Functions)** are complete black boxes—native C/C++/Rust code loaded via `:erlang.load_nif/2` that appears as normal functions but executes outside the VM. NIFs can perform arbitrary side effects: file I/O, network calls, global state modifications, or even crash the entire VM. No analysis of native code internals is possible without examining the C source, and NIFs bypass BEAM's isolation guarantees entirely. A function might appear pure but internally execute any side effect:

```elixir
defmodule FastCompare do
  def compare(a, b) do
    # NIF implementation—could do ANYTHING
    :erlang.nif_error(:nif_not_loaded)
  end
end
```

**Process-based concurrency** introduces non-deterministic message ordering, mutable process state, and cross-process communication that static analysis cannot track. Sending messages (`send/2`) is a side effect, receiving messages blocks and changes mailbox state, and GenServer state changes propagate across process boundaries. ETS (Erlang Term Storage) provides shared mutable state accessible across processes without message passing—global mutable tables that can be modified concurrently:

```elixir
:ets.new(:my_cache, [:set, :public, :named_table])

def cache_put(key, value) do
  :ets.insert(:my_cache, {key, value})  # Mutates global state
  :ok
end
```

Multiple processes mutating the same ETS table creates side effects invisible to function signatures, fundamentally incompatible with purity.

**Hot code loading** allows BEAM to maintain two versions of a module simultaneously (current and old), with processes potentially running old code while new code is available. During upgrades, the same function call might execute different code depending on when the process started and whether it jumped to new code. A "pure" function in version 1 might be impure in version 2, requiring analysis to account for multiple versions simultaneously—something static analysis cannot handle.

**OTP behaviors** like GenServer are explicitly designed for side-effectful programming. All GenServer callbacks (`handle_call`, `handle_cast`, `handle_info`) mutate server state by design, with return values determining state transitions. Supervisors dynamically start/stop/restart processes, Tasks spawn processes and manage lifecycles, and GenStage uses producers/consumers with mutable buffers. The entire OTP philosophy builds on mutable process state, message-driven transitions, and side-effectful supervision—antithetical to purity.

**Behaviors and protocols** create open-world polymorphism that breaks closed-world analysis assumptions. Any module can implement a behavior at any time, with implementation selection often determined by configuration. Protocols dispatch based on runtime type information, supporting `@derive` for automatic implementations and `@fallback_to_any` for defaults. A seemingly simple polymorphic function's purity depends on which implementation executes:

```elixir
def stringify(data) do
  String.Chars.to_string(data)  # Which impl?
end

stringify(42)  # Pure for integers
stringify(%MyStruct{})  # Might be impure for custom structs
```

## Other languages offer valuable but limited lessons

Examining how other ecosystems handle purity reveals approaches applicable to Elixir's constraints. **Haskell's IO monad** provides the gold standard for type-level purity enforcement—pure functions have types like `a -> b` while effectful functions have types like `IO a`, with the compiler preventing impure code from contaminating pure code. This approach enables strong guarantees, referential transparency, and aggressive compiler optimizations. However, it requires full static typing, complex monad transformers for stacking multiple effects (leading to N² instances), and presents a steep learning curve.

**Scala's effect systems** (Cats Effect and ZIO) demonstrate practical implementations for production use. Cats Effect provides a lightweight `IO[A]` monad with single type parameter and integration with the broader Cats ecosystem. ZIO takes a batteries-included approach with `ZIO[R, E, A]` tracking environment (R), typed errors (E), and success type (A), achieving up to 8x better performance than Cats IO in benchmarks through type-directed optimization. Both show sophisticated effect tracking can work in production with acceptable performance trade-offs.

**Academic languages** like Koka, Eff, and Effekt explore algebraic effect handlers—effects as resumable operations with user-definable control flow. Koka's row-polymorphic effect system with effect inference achieves practical performance by compiling to efficient C code and optimizing tail-resumptive effects to closures. However, these approaches require continuation support (which BEAM lacks), static typing, and language-level integration.

**Clojure** provides the most applicable model since it's also dynamically-typed and functional-but-pragmatic. Clojure relies on convention-based purity: naming pure functions with nouns and impure functions with verbs (often with `!` suffix), pushing effects to system boundaries, and programmer discipline rather than compiler enforcement. The community manages side effects through isolation patterns, explicit state management (atoms, refs, agents), and avoiding mixing side effects with lazy sequences. This approach is simple and flexible but provides no compile-time guarantees and requires extensive testing to verify purity.

**Erlang's PURITY tool** proves that bytecode-level purity analysis is viable for BEAM languages. It classifies functions into referentially transparent, side-effect free, or side-effect free with dependencies through static analysis on compiled bytecode. Successfully analyzing the entire Erlang/OTP distribution, it provides a practical foundation that could be adapted for Elixir. Its conservative approach avoids false positives (never marking impure functions as pure) while accepting some false negatives (marking some pure functions as impure due to dynamic dispatch or higher-order functions).

**Rust** tracks certain effects through its type system (ownership/borrowing, async/await, const evaluation, unsafe blocks) but lacks full algebraic effects, choosing coroutines over continuations for performance. The community debates "effect generics" to avoid code duplication between sync and async versions, but consensus remains elusive.

Key insight: **Type-level enforcement requires static typing infrastructure**. Dynamic languages like Clojure and Elixir must rely on conventions, testing, optional annotations, and conservative static analysis rather than compile-time guarantees. However, bytecode-level analysis (Erlang PURITY) combined with conventions (Clojure) and tooling (Credo, Dialyzer extensions) can provide substantial benefits without language changes.

## Practical implementation requires hybrid approach

A viable purity analysis system for Elixir must accept fundamental limitations and combine multiple strategies. **Start with conservative bytecode analysis** following the Erlang PURITY model: analyze compiled BEAM bytecode with debug_info, identify obvious side-effecting operations (IO.*, File.*, Process.*, :ets.*, :erlang.send, etc.), build call graphs using XREF-like digraph representation, and propagate impurity through fixed-point iteration. Mark unknown/dynamic calls as potentially impure by default.

**Support gradual annotation** allowing developers to mark functions as pure:
```elixir
@spec pure_computation(integer()) :: integer()
@pure true
def pure_computation(x), do: x * 2
```

Tooling verifies these claims by checking that annotated functions don't call known-impure functions, don't perform direct side effects, and don't use dynamic dispatch. Violations trigger warnings during compilation.

**Integrate with existing tools**. Create Credo checks enforcing naming conventions (functions with side effects should have `!` suffix or use IO/Agent/GenServer modules explicitly), detecting IO operations in inappropriate contexts, and suggesting pure alternatives. Extend Dialyzer to track purity in success typings, mark known-pure standard library functions, and propagate purity information through call graphs.

**Handle dynamic features conservatively**. For dynamic dispatch via apply/3 or module variables, assume all effects unless annotations specify otherwise. For macros, analyze expanded AST and track macro expansions to identify code generation patterns. For NIFs, maintain whitelist of known-pure NIFs (rare) and assume impure by default. For protocols, analyze each implementation separately and mark functions as pure only if all implementations are pure.

**Cache analysis results** to enable incremental analysis. Store per-module summaries with function purity information, track dependencies to reanalyze only changed modules, and reuse summaries for library code across projects.

Example summary structure:
```elixir
%{
  module: MyModule,
  version: "1.0.0",
  summaries: %{
    {:calculate, 2} => %{
      pure?: true,
      effects: [],
      calls: []
    },
    {:save, 1} => %{
      pure?: false,
      effects: [:io, :database],
      calls: [{DB, :insert, 2}]
    }
  }
}
```

**Build supporting infrastructure** including Mix tasks for project-wide analysis, IDE integration showing purity information inline, documentation generation with purity badges in ExDoc, and testing helpers for verifying purity claims with property-based testing.

## Limitations demand realistic expectations

Any Elixir purity analysis system faces unavoidable constraints. **Undecidability** means some pure functions will be misclassified as impure due to dynamic dispatch, higher-order functions, or conservative approximations. Complete accuracy is mathematically impossible for Turing-complete languages.

**Dynamic code paths** chosen at runtime through configuration, feature flags, or user input cannot be analyzed statically. Functions pure in one configuration might be impure in another. Runtime code compilation (`Code.compile_string/2`) and evaluation (`Code.eval_string/3`) inject code that cannot be analyzed at compile time.

**Message passing effects** span process boundaries, making transitive analysis incomplete. When a function sends a message that eventually triggers IO in another process, the effect chain is invisible to static analysis. Process mailboxes and selective receive create non-deterministic behavior that violates referential transparency even when functions appear pure.

**Macros and metaprogramming** generate different code in different contexts—development versus production builds, different configuration settings, or different target platforms. Analysis must account for all possible expansions or focus on specific configurations.

**Performance trade-offs** between precision and speed require compromise. Context-sensitive analysis with unlimited context depth is theoretically most precise but computationally intractable. Practical systems use context-insensitive interprocedural analysis or k-limited context sensitivity (typically k=1 or k=2), accepting reduced precision for reasonable performance.

**Ecosystem adoption** requires community buy-in, gradual migration paths, and clear value propositions. Existing codebases cannot be rewritten, so tools must work with legacy code. Libraries lack purity annotations, so conservative assumptions are necessary. The community must see tangible benefits in improved testing, documentation, or performance to justify adoption costs.

## Theoretical possibility meets practical feasibility

Implementing purity analysis for Elixir is **theoretically possible** within well-defined constraints. Static analysis can identify obvious side effects (IO operations, process spawning, ETS mutations), construct call graphs for statically-determinable function calls, propagate purity information through fixed-point iteration, and classify significant portions of typical codebases into pure versus impure categories. The Erlang PURITY tool proves this approach works for BEAM languages.

However, **practical feasibility faces significant challenges**. Complete purity verification is impossible due to dynamic dispatch, metaprogramming, NIFs, message passing, hot code loading, and open-world polymorphism. Conservative approximations misclassify many pure functions as impure, particularly with higher-order functions and dynamic dispatch. The analysis cannot prove purity—only detect obvious impurity.

**The most promising path forward** combines multiple strategies: conservative static analysis on BEAM bytecode (adapt Erlang PURITY), optional developer annotations verified by tooling (@pure attributes), convention-based practices (naming patterns, module organization), Credo/Dialyzer integration for enforcement, IDE support for inline purity information, and comprehensive testing infrastructure for runtime verification.

This hybrid approach provides immediate value—better documentation, improved testability, catching obvious mistakes, supporting incremental adoption—without requiring language changes or rewriting existing code. Developers opt into stricter checking via annotations while benefiting from analysis of dependencies. Tools warn about potential issues rather than enforcing strict guarantees.

The Elixir community should focus on **achievable goals** rather than perfect purity verification. Build tooling that identifies 80% of side effects with high confidence, document purity claims for library functions, establish conventions for pure versus impure code organization, and integrate analysis into development workflows (editors, CI/CD, code review). Accept that edge cases exist, dynamic code requires runtime verification, and pragmatism trumps theoretical purity.

**Bottom line**: Yes, you can build a purity analysis system for Elixir that provides substantial value despite limitations. Model it after Erlang's PURITY tool for static analysis, adopt Clojure's conventions for community practices, learn from Koka's effect handlers for theoretical foundations, and integrate with existing tools (Dialyzer, Credo) rather than building from scratch. The result won't match Haskell's compile-time guarantees but will significantly improve code quality, testing, and documentation in a language fundamentally designed for concurrent, fault-tolerant systems rather than mathematical purity.