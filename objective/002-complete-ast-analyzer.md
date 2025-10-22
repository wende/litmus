# Objective 002: Complete AST Analyzer

## Objective
Replace the outdated PURITY analyzer (from 2011) with a complete, modern AST-based analyzer that can handle all Elixir constructs including maps, structs, protocols, and modern syntax.

## Description
PURITY cannot parse Elixir maps (added 2014) and marks modern code as :unknown, contributing to 40% of unknown classifications. The new analyzer will directly analyze Elixir AST and Erlang abstract format, providing complete coverage of all language constructs with proper pattern matching, guard analysis, and macro expansion support.

### Key Problems Solved
- PURITY crashes on map syntax → :unknown
- No support for structs, protocols, or modern Elixir features
- Cannot analyze Erlang modules properly
- Missing guard analysis for exception detection

## Testing Criteria
1. **Language Coverage**
   - Handles all Elixir syntax (maps, structs, protocols, macros)
   - Analyzes Erlang abstract format correctly
   - Pattern matching in all contexts
   - Guard expressions properly analyzed
   - Macro expansion with context preservation

2. **Accuracy**
   - 100% of standard library functions correctly classified
   - Protocol dispatch resolution >80% accuracy
   - No crashes on any valid Elixir/Erlang code
   - Conservative inference when uncertain

3. **Integration**
   - Drop-in replacement for PURITY
   - Same or better performance
   - Compatible with existing registry format
   - Works with both source and BEAM files

## Detailed Implementation Guidance

### File: `lib/litmus/analyzer/complete.ex`

```elixir
defmodule Litmus.Analyzer.Complete do
  @moduledoc """
  Complete AST-based analyzer replacing PURITY.
  Handles all modern Elixir/Erlang constructs.
  """

  def analyze(mfa) do
    case find_source(mfa) do
      {:ok, source} -> analyze_source(source)
      {:error, :no_source} -> analyze_beam(mfa)
      {:error, :no_beam} -> conservative_inference(mfa)
    end
  end

  defp analyze_source(source) do
    # Parse and analyze Elixir AST
    # Handle all constructs including maps, structs, protocols
  end

  defp analyze_beam(mfa) do
    # Get abstract format from BEAM
    # Convert to analyzable form
    # Analyze Erlang constructs
  end

  defp conservative_inference(mfa) do
    # Use naming conventions as hints
    # Default to :side_effects not :unknown
  end
end
```

### Key Components

1. **AST Analysis Engine**
   - Walk all AST nodes
   - Track variable bindings
   - Handle pattern matching
   - Analyze guards
   - Process macro expansions

2. **Erlang Abstract Format Handler**
   ```elixir
   def analyze_erlang_module(module) do
     {:ok, {_, [{:abstract_code, {_, abstract_code}}]}} =
       :beam_lib.chunks(:code.which(module), [:abstract_code])

     analyze_forms(abstract_code)
   end
   ```

3. **Protocol Resolution**
   - Static resolution for built-in types
   - Track struct definitions
   - Conservative fallback for dynamic dispatch

4. **Conservative Inference**
   - Never return :unknown when avoidable
   - Use effect hierarchy (Unknown > NIF > Side > Dependent > Exception > Lambda > Pure)
   - Document assumptions

### Features to Implement
- Map literal support (`%{key: value}`)
- Struct support (`%MyStruct{}`)
- Protocol implementation tracking
- With expressions
- For comprehensions
- Binary pattern matching
- Try/rescue/after blocks
- Receive blocks

## State of Project After Implementation

### Improvements
- **Unknown classifications**: Reduced from ~10% to ~5%
- **PURITY compatibility**: No longer needed
- **Modern language support**: 100% Elixir/Erlang coverage
- **Analysis accuracy**: Improved by 40%

### New Capabilities
- Analyze any valid Elixir/Erlang code
- Protocol effect tracking
- Struct field access analysis
- Macro-aware analysis
- Better error messages with AST locations

### Files Modified
- Created: `lib/litmus/analyzer/complete.ex`
- Created: `lib/litmus/analyzer/erlang_handler.ex`
- Deprecated: References to PURITY in `lib/litmus.ex`
- Modified: `lib/litmus/registry/builder.ex`

### Removed Dependencies
- `purity_source/` directory (entire PURITY codebase)
- PURITY compilation steps
- PURITY-specific workarounds

## Next Recommended Objective

**Objective 004: CPS Transformation Completion**

With complete AST analysis in place, the next priority is extending the CPS transformer to handle all control flow constructs (cond, with, recursive functions). This enables the effect macro to work with any Elixir code pattern, providing complete algebraic effects support for testing and mocking.