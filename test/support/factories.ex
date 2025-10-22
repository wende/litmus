defmodule Test.Factories do
  @moduledoc """
  Test data factories for common patterns used across test files.

  This module provides factory functions to generate:
  - Module definitions with various function types
  - Test data for different effect scenarios
  """

  require Logger

  @doc """
  Creates a module source code string with the given name and functions.

  ## Parameters
  - module_name: Name of the module (atom or string)
  - functions: List of function definition strings

  ## Returns
  - Complete module source code string
  """
  def create_module_source(module_name, functions) when is_list(functions) do
    module_name_str = if is_atom(module_name), do: to_string(module_name), else: module_name
    function_code = Enum.join(functions, "\n\n  ")

    """
    defmodule #{module_name_str} do
      #{function_code}
    end
    """
  end

  def create_module_source(module_name, function_def) do
    create_module_source(module_name, [function_def])
  end

  @doc """
  Factory for pure function definitions.
  """
  def pure_functions do
    %{
      simple_arithmetic: "def add(x, y), do: x + y",
      string_operations: "def process_string(s), do: s |> String.upcase() |> String.trim()",
      list_operations: "def sum_list(list), do: Enum.sum(list)",
      map_operations: "def get_value(map, key), do: Map.get(map, key)",
      tuple_operations: "def first_element(tuple), do: elem(tuple, 0)",
      pipeline: "def process(data), do: data |> Enum.map(&(&1 * 2)) |> Enum.sum()",
      multiple_args: "def combine(a, b, c), do: a + b * c",
      pattern_match: "def process({:ok, value}), do: value * 2"
    }
  end

  @doc """
  Factory for effectful function definitions (side effects).
  """
  def effectful_functions do
    %{
      io_puts: "def log(message), do: IO.puts(message)",
      io_inspect: "def debug(data), do: IO.inspect(data, label: \"Debug\")",
      file_write: "def save(path, content), do: File.write!(path, content)",
      file_read: "def load(path), do: File.read!(path)",
      process_send: "def send_message(pid, msg), do: send(pid, msg)",
      system_env: "def get_env(key), do: System.get_env(key)",
      logger_info: "def log_info(message), do: Logger.info(message)",
      mixed_effects:
        "def process_and_save(data), do: IO.inspect(data); File.write!(\"out.txt\", data)"
    }
  end

  @doc """
  Factory for exception-throwing function definitions.
  """
  def exception_functions do
    %{
      argument_error:
        "def validate_positive(x), do: if x < 0, do: raise(ArgumentError, \"must be positive\")",
      runtime_error: "def must_succeed, do: raise(\"Something went wrong\")",
      custom_error: "def custom_error, do: raise(CustomError, message: \"custom failure\")",
      hd_unsafe: "def first(list), do: hd(list)",
      div_unsafe: "def divide(x, y), do: div(x, y)",
      case_exception: """
      def handle_result(result) do
        case result do
          :error -> raise ArgumentError, "invalid result"
          value -> value
        end
      end
      """,
      conditional_raise: """
      def check_value(x) do
        if x == nil do
          raise ArgumentError, "value cannot be nil"
        else
          x * 2
        end
      end
      """
    }
  end

  @doc """
  Factory for lambda-dependent (higher-order) function definitions.
  """
  def lambda_dependent_functions do
    %{
      simple_map: "def map_list(list, func), do: Enum.map(list, func)",
      simple_filter: "def filter_list(list, pred), do: Enum.filter(list, pred)",
      simple_reduce: "def reduce_list(list, acc, func), do: Enum.reduce(list, acc, func)",
      with_args: "def apply_func(func, x, y), do: func.(x, y)",
      nested: "def nested_compose(data, f, g), do: data |> Enum.map(f) |> Enum.filter(g)",
      multiple_funcs: "def combine(f, g, x), do: g.(f.(x))"
    }
  end

  @doc """
  Factory for unknown effect function definitions.
  """
  def unknown_functions do
    %{
      apply_dynamic: "def dynamic_call(m, f, a), do: apply(m, f, a)",
      apply_kernel: "def kernel_apply(func, args), do: apply(func, args)",
      eval_string: "def eval_code(code), do: Code.eval_string(code)",
      unknown_module: "def call_unknown, do: UnknownModule.some_function()"
    }
  end

  @doc """
  Factory for dependent effect function definitions.
  """
  def dependent_functions do
    %{
      system_time: "def current_time, do: System.system_time()",
      process_dict: "def get_process_value(key), do: Process.get(key)",
      self_pid: "def current_pid, do: self()",
      node_name: "def current_node, do: node()",
      ets_lookup: "def ets_get(table, key), do: :ets.lookup(table, key)"
    }
  end

  @doc """
  Factory for lambda function patterns.
  """
  def lambda_patterns do
    %{
      simple_var: "fn x -> x * 2 end",
      tuple_pattern: "fn {a, b} -> a + b end",
      list_pattern: "fn [h|t] -> h end",
      map_pattern: "fn %{key: value} -> value end",
      multiple_args: "fn x, y -> x + y end",
      with_guard: "fn x when x > 0 -> x * 2 end",
      multi_clause: """
      fn
        0 -> 0
        x -> x * 2
      end
      """,
      complex_pattern: "fn %{data: {x, y}} -> x + y end",
      nested_pattern: "fn [{a, b} | rest] -> a + b end"
    }
  end

  @doc """
  Factory for function definition patterns with pattern matching.
  """
  def function_pattern_definitions do
    %{
      simple_vars: "def add(x, y), do: x + y",
      tuple_param: "def process_tuple({a, b}), do: a + b",
      nested_tuple: "def deep({{a, b}, c}), do: a + b + c",
      list_param: "def head_tail([h|t]), do: h",
      map_param: "def extract_name(%{name: n}), do: n",
      mixed_params: "def combine({a, b}, x, [h|t]), do: a + b + x + h",
      with_guard: "def positive({a, b}) when a > 0 and b > 0, do: a + b",
      multiple_clauses: """
      def handle(:ok), do: true
      def handle({:error, _}), do: false
      def handle(_), do: :unknown
      """,
      struct_pattern: "def process_user(%User{name: name, age: age}), do: \"\#{name} (\#{age})\""
    }
  end

  @doc """
  Creates test modules for different effect categories.
  """
  def create_effect_test_modules do
    %{
      pure_module: create_module_source("PureTestModule", Map.values(pure_functions())),
      effectful_module:
        create_module_source("EffectfulTestModule", Map.values(effectful_functions())),
      exception_module:
        create_module_source("ExceptionTestModule", Map.values(exception_functions())),
      lambda_module:
        create_module_source("LambdaTestModule", Map.values(lambda_dependent_functions())),
      unknown_module: create_module_source("UnknownTestModule", Map.values(unknown_functions())),
      dependent_module:
        create_module_source("DependentTestModule", Map.values(dependent_functions()))
    }
  end

  @doc """
  Creates complex test scenarios combining multiple effect types.
  """
  def complex_scenarios do
    %{
      mixed_pipeline: """
      def mixed_pipeline(data) do
        data
        |> Enum.map(fn x -> x * 2 end)  # pure lambda
        |> IO.inspect(label: "Doubled")  # side effect
        |> Enum.filter(&(&1 > 10))      # pure lambda
        |> File.write!("output.txt")     # side effect
      end
      """,
      exception_in_pipeline: """
      def exception_pipeline(items) do
        items
        |> Enum.map(fn x -> x * 2 end)
        |> hd()  # Can raise if empty
        |> Integer.to_string()
      end
      """,
      higher_order_with_effects: """
      def process_with_logging(list, processor) do
        IO.puts("Starting processing")
        result = Enum.map(list, processor)
        IO.puts("Processing complete")
        result
      end
      """,
      conditional_effects: """
      def conditional_save(data, should_save) do
        processed = Enum.map(data, fn x -> x * 2 end)
        if should_save do
          File.write!("output.txt", inspect(processed))
        end
        processed
      end
      """,
      nested_higher_order: """
      def nested_process(data, outer_func, inner_func) do
        data
        |> Enum.map(outer_func)
        |> Enum.map(inner_func)
        |> Enum.sum()
      end
      """
    }
  end

  @doc """
  Creates test data for pattern matching in various contexts.
  """
  def pattern_matching_data do
    %{
      tuples: [
        {:ok, "success"},
        {:error, "failure"},
        {1, 2, 3},
        {{:nested, "inner"}, "outer"}
      ],
      lists: [
        [1, 2, 3],
        [_head | _tail] = [1, 2, 3],
        [],
        [{:a, 1}, {:b, 2}]
      ],
      maps: [
        %{key: "value", count: 42},
        %{user: %{name: "Alice", age: 30}},
        %{}
      ],
      structs: [
        %Test.Exceptions.CustomError{message: "test"},
        %{__struct__: User, name: "Bob", age: 25}
      ]
    }
  end

  @doc """
  Creates test data for cross-module function calls.
  """
  def cross_module_test_data do
    helper_module = """
    defmodule TestHelper do
      def pure_func(x), do: x * 2
      def effectful_func(x), do: IO.puts("\#{x}"); x * 2
      def exception_func(x), do: if x < 0, do: raise(ArgumentError), else: x
      def lambda_func(func), do: func.(42)
    end
    """

    caller_module = """
    defmodule TestCaller do
      def call_pure(x), do: TestHelper.pure_func(x)
      def call_effectful(x), do: TestHelper.effectful_func(x)
      def call_exception(x), do: TestHelper.exception_func(x)
      def call_lambda(func), do: TestHelper.lambda_func(func)
    end
    """

    %{helper: helper_module, caller: caller_module}
  end

  @doc """
  Creates source code with specific effect types for targeted testing.
  """
  def create_effect_specific_source(effect_type) do
    case effect_type do
      :pure ->
        create_module_source("PureTest", [
          "def add(x, y), do: x + y",
          "def process(list), do: Enum.map(list, &(&1 * 2))"
        ])

      :side_effects ->
        create_module_source("EffectfulTest", [
          "def log(message), do: IO.puts(message)",
          "def save(data), do: File.write!(\"out.txt\", data)"
        ])

      :exceptions ->
        create_module_source("ExceptionTest", [
          "def validate(x), do: if x < 0, do: raise(ArgumentError)",
          "def unsafe_head(list), do: hd(list)"
        ])

      :lambda ->
        create_module_source("LambdaTest", [
          "def map_list(list, func), do: Enum.map(list, func)",
          "def apply_func(func, x), do: func.(x)"
        ])

      :unknown ->
        create_module_source("UnknownTest", [
          "def dynamic_call(m, f, a), do: apply(m, f, a)",
          "def unknown_module, do: UnknownModule.func()"
        ])

      :dependent ->
        create_module_source("DependentTest", [
          "def get_time, do: System.system_time()",
          "def get_self, do: self()"
        ])
    end
  end
end
