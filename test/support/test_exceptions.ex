defmodule Test.Exceptions do
  @moduledoc """
  Shared exception modules for testing across multiple test files.

  This module defines common exception types used in tests to avoid duplication
  and provide consistent exception testing patterns.
  """

  defmodule CustomError do
    defexception [:message]

    @impl true
    def message(%{message: message}) do
      "Custom error: #{message}"
    end
  end

  defmodule DomainError do
    defexception [:message, :domain]

    @impl true
    def message(%{message: message, domain: domain}) do
      "Domain error (#{domain}): #{message}"
    end
  end

  defmodule ValidationError do
    defexception [:field, :reason]

    @impl true
    def message(%{field: field, reason: reason}) do
      "Validation error: #{field} - #{reason}"
    end
  end

  defmodule BusinessError do
    defexception [:code, :details]

    @impl true
    def message(%{code: code, details: details}) do
      "Business error #{code}: #{details}"
    end
  end

  defmodule NetworkError do
    defexception [:host, :port, :reason]

    @impl true
    def message(%{host: host, port: port, reason: reason}) do
      "Network error connecting to #{host}:#{port} - #{reason}"
    end
  end

  @doc """
  Creates a function that raises a specific exception type.

  ## Parameters
  - exception_module: The exception module to raise
  - message: Optional message (defaults to "Test exception")
  - extra_fields: Optional map of extra fields for the exception

  ## Returns
  - Function that raises the specified exception when called
  """
  def create_exception_raiser(exception_module, message \\ "Test exception", extra_fields \\ %{}) do
    fn ->
      base_fields = [message: message]
      all_fields = Map.merge(extra_fields, base_fields)

      case Map.to_list(all_fields) do
        [] -> raise exception_module
        fields -> raise exception_module, fields
      end
    end
  end

  @doc """
  Creates a function that raises an exception with specific arguments.

  ## Parameters
  - exception_module: The exception module to raise
  - args: List of arguments to pass to the exception constructor

  ## Returns
  - Function that raises the specified exception when called
  """
  def create_exception_raiser_with_args(exception_module, args) do
    fn ->
      apply(exception_module, :exception, args)
      |> raise()
    end
  end

  @doc """
  List of all test exception modules for easy iteration in tests.
  """
  def all_exception_modules do
    [
      CustomError,
      DomainError,
      ValidationError,
      BusinessError,
      NetworkError
    ]
  end

  @doc """
  Creates a map of sample exception instances for testing.
  """
  def sample_exceptions do
    %{
      custom: %CustomError{message: "Custom test error"},
      domain: %DomainError{message: "Invalid domain", domain: "test"},
      validation: %ValidationError{field: :email, reason: "invalid format"},
      business: %BusinessError{code: "BIZ001", details: "Business rule violation"},
      network: %NetworkError{host: "example.com", port: 80, reason: "timeout"}
    }
  end

  @doc """
  Creates functions that raise different types of exceptions for testing.
  """
  def exception_raising_functions do
    %{
      argument_error: fn -> raise ArgumentError, "Invalid argument" end,
      runtime_error: fn -> raise RuntimeError, "Runtime failure" end,
      custom_error: fn -> raise CustomError, message: "Custom failure" end,
      domain_error: fn -> raise DomainError, message: "Domain violation", domain: "test" end,
      validation_error: fn -> raise ValidationError, field: :age, reason: "too young" end,
      business_error: fn -> raise BusinessError, code: "BIZ001", details: "Rule broken" end,
      network_error: fn -> raise NetworkError, host: "test.com", port: 443, reason: "refused" end,
      string_raise: fn -> raise "String exception" end,
      throw_value: fn -> throw(:test_value) end,
      exit_process: fn -> exit(:test_exit) end
    }
  end

  @doc """
  Creates lambda functions that raise exceptions for testing higher-order functions.
  """
  def exception_lambdas do
    %{
      argument_error_lambda: fn x ->
        if x < 0, do: raise(ArgumentError, "Negative value not allowed"), else: x * 2
      end,
      custom_error_lambda: fn x ->
        if x == :error, do: raise(CustomError, message: "Error token", else: x)
      end,
      domain_error_lambda: fn {domain, value} ->
        if domain == :invalid,
          do: raise(DomainError, message: "Invalid domain", domain: domain, else: value)
      end,
      validation_lambda: fn %{field: field, value: value} ->
        if is_nil(value),
          do: raise(ValidationError, field: field, reason: "cannot be nil", else: value)
      end,
      multi_exception_lambda: fn input ->
        case input do
          nil -> raise ArgumentError, "Input cannot be nil"
          :error -> raise CustomError, message: "Error state"
          {:domain, domain} -> raise DomainError, message: "Bad domain", domain: domain
          x -> x
        end
      end
    }
  end

  @doc """
  Creates test data with various exception scenarios for pattern matching tests.
  """
  def exception_test_data do
    %{
      simple_raise: "raise ArgumentError, \"Simple error\"",
      raise_with_struct: "raise %CustomError{message: \"Struct error\"}",
      conditional_raise: """
      if value < 0 do
        raise ArgumentError, "Negative value"
      else
        value * 2
      end
      """,
      case_raise: """
      case type do
        :arg -> raise ArgumentError
        :runtime -> raise RuntimeError
        :custom -> raise CustomError, message: "Custom"
      end
      """,
      try_catch_raise: """
      try do
        risky_operation()
      rescue
        ArgumentError -> :handled
      end
      """
    }
  end
end
