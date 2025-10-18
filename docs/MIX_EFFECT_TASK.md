# Mix Effect Task

The `mix effect` task analyzes Elixir source files and displays all functions with their inferred effects and exceptions.

## Usage

```bash
mix effect path/to/file.ex [options]
```

## Options

- `--verbose`, `-v` - Show detailed analysis including type information
- `--json` - Output results in JSON format for tooling integration
- `--exceptions` - Include exception analysis (requires compiled module)
- `--purity` - Include purity analysis from PURITY analyzer

## Examples

### Basic Effect Analysis

```bash
mix effect lib/my_module.ex
```

Output:
```
Analyzing: lib/my_module.ex

═══════════════════════════════════════════════════════════
Module: MyModule
═══════════════════════════════════════════════════════════

read_file/1
  ───────────────────────────────────────────────────────
  ⚡ Effectful
  Effects: ⟨file⟩
    Detected effects:
      • file: File system operations
  Calls:
    ⚡ Elixir.File.read!/1

greet/1
  ───────────────────────────────────────────────────────
  ⚡ Effectful
  Effects: ⟨io⟩
    Detected effects:
      • io: Input/output operations
  Calls:
    ⚡ Elixir.IO.puts/1

═══════════════════════════════════════════════════════════
Summary: 2 functions analyzed
  ✓ Pure: 0
  ⚡ Effectful: 2
═══════════════════════════════════════════════════════════
```

### Verbose Output with Type Information

```bash
mix effect lib/my_module.ex --verbose
```

Adds type signatures to the output:
```
read_file/1
  ───────────────────────────────────────────────────────
  ⚡ Effectful
  Effects: ⟨file⟩
    Detected effects:
      • file: File system operations
  Type: t0 -> ⟨file⟩ t1
  Return: t1
  Calls:
    ⚡ Elixir.File.read!/1
```

### JSON Output for Tooling

```bash
mix effect lib/my_module.ex --json
```

Produces structured JSON output suitable for editor integration, CI/CD pipelines, or custom tooling:

```json
{
  "module": "MyModule",
  "functions": [
    {
      "name": "read_file",
      "arity": 1,
      "effect": "⟨file⟩",
      "effect_labels": ["file"],
      "is_pure": false,
      "type": "t0 -> ⟨file⟩ t1",
      "return_type": "t1",
      "visibility": "def",
      "calls": [
        {"module": "Elixir.File", "function": "read!", "arity": 1}
      ],
      "line": 5
    }
  ],
  "errors": []
}
```

## Effect Types

The analyzer tracks the following effect categories:

| Effect | Description | Examples |
|--------|-------------|----------|
| `⟨⟩` (pure) | No side effects | Pure computation, transformations |
| `⟨io⟩` | Input/output operations | `IO.puts`, `IO.gets` |
| `⟨file⟩` | File system operations | `File.read!`, `File.write!` |
| `⟨process⟩` | Process operations | `spawn`, `send`, `receive` |
| `⟨state⟩` | Stateful operations | `Agent`, mutable state |
| `⟨exn⟩` | Can raise exceptions | `hd/1`, `div/2` |
| `⟨network⟩` | Network operations | HTTP requests, TCP/UDP |
| `⟨ets⟩` | ETS table operations | `:ets.insert`, `:ets.lookup` |
| `⟨time⟩` | Time-dependent operations | `System.system_time` |
| `⟨random⟩` | Random number generation | `:rand.uniform` |
| `⟨nif⟩` | Native implemented functions | NIFs |
| `¿` (unknown) | Unknown effects | Unannotated or unanalyzed code |

## Understanding the Output

### Pure Functions

Functions with no side effects are marked with a green checkmark:

```
✓ Pure
Effects: ⟨⟩
```

### Effectful Functions

Functions with side effects show:
1. A lightning bolt indicator (⚡)
2. The combined effect type using row polymorphism
3. A breakdown of detected effects
4. Function calls made (with effect indicators)

Example:
```
log_and_save/2
  ⚡ Effectful
  Effects: ⟨file | io⟩
    Detected effects:
      • file: File system operations
      • io: Input/output operations
  Calls:
    ⚡ Elixir.IO.puts/1
    ⚡ Elixir.File.write!/2
```

### Unknown Effects

The `¿` (unknown effect) indicates:
- Functions from modules not yet analyzed
- Dynamically dispatched code
- Metaprogramming constructs

This is part of the **gradual effect system** - code can be incrementally annotated and analyzed.

### Call Indicators

In the calls list:
- `✓` (green) - Pure function call
- `⚡` (yellow) - Effectful function call

## Row-Polymorphic Effects

Effects are represented using row polymorphism with support for duplicate labels:

```
⟨file | io⟩         - File and IO effects
⟨exn | exn⟩         - Nested exception contexts
⟨process | ¿⟩       - Process effect plus unknown effects
```

This representation enables:
- **Principal type inference** - unique, most general types
- **Proper nesting** - duplicate labels for nested handlers
- **Effect polymorphism** - functions polymorphic over effects

## Integration with CI/CD

Use the JSON output for automated checking:

```bash
#!/bin/bash
# Check that critical modules remain pure

mix effect lib/critical/math.ex --json | \
  jq -e '.functions | all(.is_pure == true)' || \
  (echo "Error: Critical module contains impure functions" && exit 1)
```

## Limitations

1. **Static Analysis Only** - Cannot analyze dynamic dispatch or runtime-constructed code
2. **Gradual System** - Unknown effects (¿) require runtime analysis or annotations
3. **Pattern Matching** - Complex pattern matching may not be fully analyzed
4. **Metaprogramming** - Macros and compile-time code generation have limited support

## Advanced Features

### Row Polymorphism

The effect system uses row-polymorphic effects based on research from Koka and bidirectional typing:

- Effects can be extended: `⟨new_effect | existing_effects⟩`
- Effects can be removed by handlers
- Duplicate labels supported for nested contexts

### Bidirectional Type Inference

The analyzer uses two modes:
- **Synthesis (⇒)** - Infers types bottom-up from expressions
- **Checking (⇐)** - Verifies expressions against expected types

This enables handling of higher-rank polymorphism while maintaining decidability.

## Examples

### Example 1: Pure Mathematical Functions

```elixir
defmodule Math do
  def add(x, y), do: x + y
  def multiply(x, y), do: x * y
end
```

```bash
$ mix effect lib/math.ex
```

Shows both functions as having unknown effects (¿) because basic arithmetic operators are not yet in the effect registry. With full purity analysis, these would be pure.

### Example 2: Effectful I/O

```elixir
defmodule Logger do
  def log_info(msg) do
    IO.puts("[INFO] #{msg}")
  end

  def log_to_file(path, msg) do
    File.write!(path, msg)
  end
end
```

```bash
$ mix effect lib/logger.ex
```

Shows:
- `log_info/1` with `⟨io⟩` effect
- `log_to_file/2` with `⟨file⟩` effect

### Example 3: Mixed Effects

```elixir
defmodule Pipeline do
  def process(input_path, output_path) do
    data = File.read!(input_path)
    IO.puts("Processing...")
    result = String.upcase(data)
    File.write!(output_path, result)
    :ok
  end
end
```

```bash
$ mix effect lib/pipeline.ex --verbose
```

Shows `process/2` with combined `⟨file | io⟩` effect and full type signature.

## See Also

- [Type and Effect System Documentation](./TYPE_EFFECT_SYSTEM.md)
- [Bidirectional Effects Inference Research](./BIDIRECTION_EFFECTS_INFERENCE.md)
- Litmus purity analysis: `Litmus.analyze_module/2`
- Exception tracking: `Litmus.analyze_exceptions/2`

## Contributing

To add new effect categories or improve analysis:

1. Add effect labels to `Litmus.Types.Core`
2. Register functions in `Litmus.Effects.Registry`
3. Update effect descriptions in `Mix.Tasks.Effect`
4. Add tests demonstrating the new effects