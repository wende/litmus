# Elixir Standard Library Purity Analysis

**Generated:** 2025-10-16T22:57:57.004093Z

## Purity Statistics

| Metric | Count | Percentage |
|--------|-------|------------|
| **Total functions** | 3114 | 100.00% |
| **Modules analyzed** | 124 | - |

### By Purity Level

| Purity Level | Functions | Percentage |
|--------------|-----------|------------|
| Pure | 2723 | 87.44% |
| Side Effects | 194 | 6.23% |
| Dependent | 97 | 3.11% |
| Unknown | 100 | 3.21% |

## Exception Statistics

| Exception Type | Functions | Percentage |
|----------------|-----------|------------|
| **Total analyzed** | 4882 | 100.00% |
| Pure (no exceptions) | 2811 | 57.58% |
| Raises typed errors | 2058 | 42.15% |
| Can throw/exit | 64 | 1.31% |
| Dynamic exceptions | 1967 | 40.29% |

## Module Analysis

| Module | Functions | Pure | Side Effects | Dependent | Unknown |
|--------|-----------|------|--------------|-----------|---------|
| Stream | 190 | 150 | 2 | 1 | 37 |
| String | 146 | 142 | 2 | 1 | 1 |
| File | 109 | 91 | 2 | 1 | 15 |
| Module.Types.Unify | 105 | 97 | 2 | 1 | 5 |
| IO.ANSI | 96 | 93 | 2 | 1 | 0 |
| Keyword | 91 | 88 | 2 | 1 | 0 |
| System | 84 | 75 | 2 | 1 | 6 |
| Kernel.Typespec | 81 | 78 | 2 | 1 | 0 |
| Mix.ProjectStack | 78 | 75 | 2 | 1 | 0 |
| Logger | 71 | 65 | 2 | 1 | 3 |
| List | 71 | 67 | 2 | 1 | 1 |
| Task | 69 | 66 | 2 | 1 | 0 |
| Module.Types.Pattern | 68 | 61 | 2 | 1 | 4 |
| Map | 60 | 57 | 2 | 1 | 0 |
| Module.Types | 58 | 55 | 2 | 1 | 0 |
| Task.Supervised | 55 | 46 | 2 | 1 | 6 |
| OptionParser | 54 | 51 | 2 | 1 | 0 |
| Kernel.CLI | 52 | 44 | 2 | 1 | 5 |
| Inspect.Algebra | 51 | 47 | 2 | 1 | 1 |
| Mix.Dep | 51 | 48 | 2 | 1 | 0 |
| Regex | 51 | 48 | 2 | 1 | 0 |
| Path | 46 | 43 | 2 | 1 | 0 |
| Mix.SCM.Git | 45 | 42 | 2 | 1 | 0 |
| Kernel.LexicalTracker | 43 | 40 | 2 | 1 | 0 |
| Process | 43 | 40 | 2 | 1 | 0 |
| IO | 43 | 40 | 2 | 1 | 0 |
| Access | 41 | 33 | 2 | 1 | 5 |
| Module.LocalsTracker | 37 | 34 | 2 | 1 | 0 |
| Module.Types.Expr | 36 | 33 | 2 | 1 | 0 |
| Logger.Backends.Console | 36 | 33 | 2 | 1 | 0 |
| Module.Types.Of | 36 | 30 | 2 | 1 | 3 |
| Kernel.Utils | 34 | 31 | 2 | 1 | 0 |
| MapSet | 33 | 30 | 2 | 1 | 0 |
| Agent | 33 | 30 | 2 | 1 | 0 |
| Code.Normalizer | 32 | 29 | 2 | 1 | 0 |
| Mix.Compilers.ApplicationTracer | 31 | 28 | 2 | 1 | 0 |
| GenServer | 31 | 28 | 2 | 1 | 0 |
| Integer | 31 | 28 | 2 | 1 | 0 |
| StringIO | 31 | 27 | 2 | 1 | 1 |
| Module.Types.Helpers | 30 | 25 | 2 | 1 | 2 |
| Mix.Tasks.Compile.Erlang | 29 | 26 | 2 | 1 | 0 |
| Mix.State | 28 | 25 | 2 | 1 | 0 |
| Logger.Handler | 26 | 23 | 2 | 1 | 0 |
| Supervisor | 25 | 22 | 2 | 1 | 0 |
| Macro.Env | 25 | 22 | 2 | 1 | 0 |
| String.Tokenizer | 25 | 22 | 2 | 1 | 0 |
| Logger.Config | 23 | 20 | 2 | 1 | 0 |
| Version | 22 | 19 | 2 | 1 | 0 |
| Mix.Tasks.Compile.All | 22 | 19 | 2 | 1 | 0 |
| Version.Parser | 22 | 19 | 2 | 1 | 0 |
| Logger.Formatter | 21 | 18 | 2 | 1 | 0 |
| Mix.Tasks.Compile | 21 | 18 | 2 | 1 | 0 |
| Enumerable.Stream | 20 | 16 | 2 | 1 | 1 |
| Mix.Tasks.Deps.Loadpaths | 19 | 16 | 2 | 1 | 0 |
| Mix.Tasks.Compile.Elixir | 18 | 15 | 2 | 1 | 0 |
| Code.Identifier | 17 | 12 | 2 | 1 | 2 |
| Logger.Watcher | 16 | 13 | 2 | 1 | 0 |
| Mix.SCM.Path | 16 | 13 | 2 | 1 | 0 |
| Mix.Shell.IO | 16 | 13 | 2 | 1 | 0 |
| Agent.Server | 16 | 13 | 2 | 1 | 0 |
| Mix.TasksServer | 15 | 12 | 2 | 1 | 0 |
| Version.Requirement | 15 | 12 | 2 | 1 | 0 |
| Logger.App | 15 | 12 | 2 | 1 | 0 |
| Mix.Tasks.Run | 14 | 10 | 2 | 1 | 1 |
| Mix.Shell | 14 | 11 | 2 | 1 | 0 |
| Mix.Dep.Umbrella | 13 | 10 | 2 | 1 | 0 |
| Logger.BackendSupervisor | 13 | 10 | 2 | 1 | 0 |
| Mix.Dep.Lock | 13 | 10 | 2 | 1 | 0 |
| Enumerable.List | 13 | 9 | 2 | 1 | 1 |
| File.Error | 12 | 9 | 2 | 1 | 0 |
| Mix.SCM | 12 | 9 | 2 | 1 | 0 |
| Mix.Dep.ElixirSCM | 12 | 9 | 2 | 1 | 0 |
| Enumerable.Function | 11 | 8 | 2 | 1 | 0 |
| Collectable.Mix.Shell | 9 | 6 | 2 | 1 | 0 |
| Mix.RemoteConverger | 9 | 6 | 2 | 1 | 0 |
| Collectable.Map | 9 | 6 | 2 | 1 | 0 |
| Logger.Filter | 9 | 6 | 2 | 1 | 0 |
| Path.Wildcard | 9 | 6 | 2 | 1 | 0 |
| Mix.Tasks.Archive.Check | 9 | 6 | 2 | 1 | 0 |
| Mix.Tasks.Loadpaths | 9 | 6 | 2 | 1 | 0 |
| List.Chars.BitString | 8 | 5 | 2 | 1 | 0 |
| String.Chars.Atom | 8 | 5 | 2 | 1 | 0 |
| Supervisor.Default | 7 | 4 | 2 | 1 | 0 |
| Mix.Tasks.Deps.Precompile | 7 | 4 | 2 | 1 | 0 |
| Hex.Utils | 3 | 0 | 2 | 1 | 0 |
| Hex.Config | 3 | 0 | 2 | 1 | 0 |
| Hex.Parallel | 3 | 0 | 2 | 1 | 0 |
| Hex.Server | 3 | 0 | 2 | 1 | 0 |
| Hex.SCM | 3 | 0 | 2 | 1 | 0 |
| Hex.State | 3 | 0 | 2 | 1 | 0 |
| Hex.Application | 3 | 0 | 2 | 1 | 0 |
| Hex.Registry.Server | 3 | 0 | 2 | 1 | 0 |
| Hex.UpdateChecker | 3 | 0 | 2 | 1 | 0 |
| Hex.RemoteConverger | 3 | 0 | 2 | 1 | 0 |
| Hex.Netrc.Cache | 3 | 0 | 2 | 1 | 0 |
| Hex.Repo | 3 | 0 | 2 | 1 | 0 |
| Hex | 3 | 0 | 2 | 1 | 0 |
| Mix.CLI | 0 | 0 | 0 | 0 | 0 |
| Mix.Hex | 0 | 0 | 0 | 0 | 0 |
| Kernel | 0 | 0 | 0 | 0 | 0 |
| Macro | 0 | 0 | 0 | 0 | 0 |
| Mix.Tasks.Deps.Compile | 0 | 0 | 0 | 0 | 0 |
| Mix.Dep.Converger | 0 | 0 | 0 | 0 | 0 |
| Mix.Task | 0 | 0 | 0 | 0 | 0 |
| Mix.Tasks.Compile.App | 0 | 0 | 0 | 0 | 0 |
| Mix.Tasks.Loadconfig | 0 | 0 | 0 | 0 | 0 |
| Mix.Tasks.App.Config | 0 | 0 | 0 | 0 | 0 |
| Code | 0 | 0 | 0 | 0 | 0 |
| Mix.Task.Compiler | 0 | 0 | 0 | 0 | 0 |
| Mix.Compilers.Erlang | 0 | 0 | 0 | 0 | 0 |
| Mix.Rebar | 0 | 0 | 0 | 0 | 0 |
| Module.ParallelChecker | 0 | 0 | 0 | 0 | 0 |
| Mix.Tasks.Compile.Protocols | 0 | 0 | 0 | 0 | 0 |
| Mix.Tasks.App.Start | 0 | 0 | 0 | 0 | 0 |
| Mix.Dep.Loader | 0 | 0 | 0 | 0 | 0 |
| Enum | 0 | 0 | 0 | 0 | 0 |
| Mix.Utils | 0 | 0 | 0 | 0 | 0 |
| Mix.Local | 0 | 0 | 0 | 0 | 0 |
| Mix.Compilers.Elixir | 0 | 0 | 0 | 0 | 0 |
| Mix.Project | 0 | 0 | 0 | 0 | 0 |
| Application | 0 | 0 | 0 | 0 | 0 |
| Mix | 0 | 0 | 0 | 0 | 0 |
| Code.Formatter | 0 | 0 | 0 | 0 | 0 |
| Module | 0 | 0 | 0 | 0 | 0 |

---

*Analysis performed using [Litmus](https://github.com/wende/litmus) v0.1.0*
