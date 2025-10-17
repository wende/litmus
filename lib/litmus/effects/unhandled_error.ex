defmodule Litmus.Effects.UnhandledError do
  @moduledoc """
  Exception raised when an effect is not handled by the effect handler.

  This provides better error messages than the default `CaseClauseError` or
  `FunctionClauseError` when an effect signature doesn't match any handler clause.
  """

  defexception [:effect, :args, :message]

  @impl true
  def exception(effect_sig) do
    {module, function, args} = effect_sig

    %__MODULE__{
      effect: {module, function},
      args: args,
      message: format_message(module, function, args)
    }
  end

  defp format_message(module, function, args) do
    arity = length(args)
    args_display = Enum.map_join(args, ", ", &inspect/1)

    """
    Unhandled effect: #{inspect(module)}.#{function}/#{arity}

    Effect signature:
      {#{inspect(module)}, #{inspect(function)}, [#{args_display}]}

    This effect was not handled by your catch clause. You can:
      1. Add a matching pattern to your catch block
      2. Add a wildcard pattern to pass through unhandled effects:

         catch
           # ... your specific handlers ...
           effect_sig -> Litmus.Effects.apply_effect(effect_sig)

      3. Use a default value for unhandled effects:

         catch
           # ... your specific handlers ...
           _ -> :default_value
    """
  end
end
