defmodule SubcipherWeb.AlgorithmLive.Steps.Summaries do
  @moduledoc "The steps of an algorithm, for display: number, cipher name and settings."
  alias Subcipher.Steps
  alias Subcipher.Algorithms.Algorithm
  alias Subcipher.Steps.Step

  @doc "The steps of `algorithm` as `%{number, name, settings}` (settings as text)."
  def describe(algorithm) do
    pictures =
      if Algorithm.pictures?(algorithm),
        do: [
          %{
            number: 1,
            name: "Symbol substitution",
            settings: "#{length(algorithm.symbol_key)} symbols in the key"
          }
        ],
        else: []

    offset = length(pictures) + 1

    steps =
      for {%{"type" => type, "params" => params}, number} <-
            Enum.with_index(algorithm.steps, offset) do
        cipher = Steps.cipher!(type)
        params = Steps.params(%Step{type: type, params: params})

        settings =
          if Steps.implements?(cipher, :summary, 1) && cipher.summary(params),
            do: cipher.summary(params),
            else: settings_text(cipher, params)

        %{number: number, name: cipher.name(), settings: settings}
      end

    pictures ++ steps
  end

  defp settings_text(cipher, params) do
    cipher.fields()
    |> Enum.map(fn field ->
      value =
        case Map.get(params, field.name) do
          map when is_map(map) -> "#{map_size(map)} substitutions"
          nil -> "automatic"
          "" -> "none"
          value -> to_string(value)
        end

      "#{field.label}: #{value}"
    end)
    |> Enum.join(" · ")
    |> case do
      "" -> "No settings"
      text -> text
    end
  end
end
