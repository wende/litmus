# Cache vs Fresh Analysis: How `mix effect` Works

## Quick Answer

**NO** - `mix effect` does NOT use cached analysis for the file you're analyzing.

When you run `mix effect deps/jason/lib/jason.ex`:
- ❌ It does NOT use `.effects/deps.cache` for jason.ex
- ✅ It re-analyzes jason.ex and all sibling files FRESH
- ✅ It uses cache for OTHER dependencies and project files

## Detailed Breakdown

### Scenario 1: Analyzing Project File

```bash
$ mix effect lib/my_module.ex
```

**What happens**:
1. Load deps cache (Jason, etc.) → 34 functions
2. Discover project files → lib/**/*.ex
3. Re-analyze ALL project files fresh
4. Use deps cache for Jason calls → `Jason.encode!/2 → "s"`

**Result**: Your project files get fresh analysis, dependencies use cache ✅

---

### Scenario 2: Analyzing Dependency File

```bash
$ mix effect deps/jason/lib/jason.ex
```

**What happens**:
1. Load deps cache (Jason functions) → 34 functions
2. Discover sibling files → deps/jason/lib/*.ex (10 files)
3. **Re-analyze Jason files fresh** (56 functions)
4. Use cache for OTHER dependencies

**Result**: Jason gets fresh analysis, other deps use cache ⚠️

**Output shows**:
```
Loading dependency effects from cache...        # Cache loaded
Analyzing 11 application files...               # But re-analyzing anyway!
Built effect cache with 56 functions            # Fresh analysis (not from cache)

Jason.encode!/2:
  Effects:
    • e (exn:dynamic)                           # More detailed!
    • {:s, ["IO.iodata_to_binary/1"]}
    • u (unknown)
```

**vs cached version**:
```json
"Jason.encode!/2": "s"  // Simplified (loses detail)
```

---

## Why the Difference?

### Current Architecture

```elixir
# In mix effect task:

# Step 1: Load deps cache
deps_cache = load_or_analyze_deps()
# %{{Jason, :encode!, 2} => :s, ...}

# Step 2: Discover files to analyze
app_files = discover_app_files() ++ sibling_files(requested_file)

# Step 3: Analyze them fresh (doesn't use deps_cache for these files!)
{:ok, results} = Analyzer.analyze_project(app_files)

# Step 4: Merge caches (for cross-module resolution)
full_cache = Map.merge(deps_cache, extract_cache(results))
```

**The problem**:
- `Analyzer.analyze_project(app_files)` always analyzes from source
- It doesn't check if files are already in deps_cache
- Cache is only used for cross-module calls DURING analysis

---

## Comparison Table

| Aspect | Cached Analysis | Fresh Analysis |
|--------|----------------|----------------|
| **Speed** | ⚡ Fast (~100ms) | 🐌 Slow (~2s) |
| **Context** | All dep files analyzed together | Only sibling files |
| **Detail** | Simplified (`:s`, `:p`, etc.) | Full (effects + leaves) |
| **Cross-module** | Resolved via cached functions | Some marked unknown |
| **Use case** | Project code calling deps | Analyzing deps themselves |

---

## Example: Analyzing Jason.encode!/2

### From Cache (when calling from project code)

```elixir
# Your code
def my_function(data) do
  Jason.encode!(data)  # Looks up Jason.encode!/2 in cache
end
```

**Result**: `Jason.encode!/2 → :s` (from cache)
- ✅ Fast
- ❌ Less detailed (just `:s`)
- ✅ Good enough for user code

### Fresh Analysis (when running mix effect on Jason)

```bash
$ mix effect deps/jason/lib/jason.ex
```

**Result**: Full analysis
```
Jason.encode!/2:
  Effects:
    • e (exn:dynamic)               ← Tracks exceptions
    • {:s, ["IO.iodata_to_binary/1"]} ← Shows specific calls
    • u (unknown)                   ← Unresolved calls
```

- ❌ Slower
- ✅ More detailed
- ⚠️ Some cross-module calls unknown (if not in same directory)

---

## Is This a Problem?

### For Project Code: **NO** ✅

When analyzing your project:
- Dependencies are resolved from cache (fast!)
- You get accurate effect propagation
- Good balance of speed and accuracy

### For Dependency Inspection: **Maybe** ⚠️

When analyzing a dependency file directly:
- Fresh analysis is more detailed
- But some cross-module calls may be unknown
- Slower than using cache

---

## How to Get Most Thorough Analysis

### Option 1: Trust the Cache

```bash
# Cache was built with full context
$ cat .effects/deps.cache | jq '.["Jason.encode!/2"]'
"s"
```

**Pros**: Fast, built with all Jason files together
**Cons**: Simplified format

### Option 2: Analyze Entire Dependency

```bash
# Analyze all Jason files at once
$ for file in deps/jason/lib/*.ex; do
    echo "=== $file ===" && mix effect "$file"
  done
```

**Pros**: Full detail for each file
**Cons**: Very slow

### Option 3: Re-build Cache with Verbose Mode

```bash
# Delete cache and rebuild with logging
$ rm -f .effects/deps.cache .effects/deps.checksum
$ mix effect lib/your_file.ex --verbose

# Watch as dependencies are analyzed:
# "Analyzing 10 dependency source files..."
# "Jason.encode!/2 detected as: s (side effect)"
```

**Pros**: See full analysis process
**Cons**: One-time rebuild

---

## Recommendation

**For most users**: Trust the cache! ✅

The cached analysis was built by analyzing all dependency files together with full context. It's:
- ✅ Fast (cached)
- ✅ Accurate (full context)
- ⚠️ Simplified (but sufficient for effect tracking)

**For library authors**: Analyze your own code fresh! 🔍

If you're developing a library and want thorough analysis:
```bash
# Analyze your library's files
$ mix effect lib/my_library.ex --verbose
```

This gives you:
- Full detail on effects
- Exception tracking
- Call graph information

---

## Future Enhancement (Phase 2)

We could add a `--use-cache` flag:

```bash
# Use cached analysis if available
$ mix effect deps/jason/lib/jason.ex --use-cache

# Result: Pull from .effects/deps.cache instead of re-analyzing
Jason.encode!/2: s (from cache)
```

This would:
- ✅ Be instant
- ✅ Show cached results
- ⚠️ Less detailed but faster

**Implementation**:
```elixir
def analyze_file(path, opts) do
  if opts[:use_cache] and is_dependency_file?(path) do
    # Look up in deps cache
    lookup_cached_analysis(path)
  else
    # Fresh analysis (current behavior)
    analyze_fresh(path)
  end
end
```

---

## Summary

**Current behavior**:
- Project files → Fresh analysis + deps cache for calls ✅
- Dependency files → Fresh analysis (cache not used for target file) ⚠️

**Cached analysis**:
- Simplified but accurate
- Built with full context
- Fast for project code

**Fresh analysis**:
- Detailed with all effect information
- Slower
- May have unknown cross-module calls

**Bottom line**: The cache works great for analyzing YOUR code. If you need to inspect dependency internals, `mix effect` will re-analyze them with full detail (but slower).
