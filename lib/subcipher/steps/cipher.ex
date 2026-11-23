defmodule Subcipher.Steps.Cipher do
  @moduledoc """
  Behaviour of a text cipher usable as a decoding step.

  A step takes the previous step's output and decodes it. To add a cipher
  type, implement this behaviour and list the module in
  `Subcipher.Steps.ciphers/0`:

      defmodule Subcipher.Steps.Ciphers.Atbash do
        use Subcipher.Steps.Cipher

        @impl true
        def type, do: "atbash"
        @impl true
        def name, do: "Atbash"
        @impl true
        def description, do: "Reverses the alphabet: A ↔ Z, B ↔ Y…"
        @impl true
        def fields, do: []
        @impl true
        def decode(text, _params), do: Alphabet.map_letters(text, &(25 - &1))
      end

  Parameters are described by `fields/0`; they are validated and cast with
  an Ecto changeset built from those fields (plus `validate/1`), stored as
  JSON, and rendered as a form on the puzzle page. `decode/2` receives them
  as a map with atom keys, defaults applied.

  Field types:

    * `:integer`, `:string` - a plain input. An `:integer` field can have
      `control: :range` (a slider), and its `max` can be a function of the
      step's input. With a `nil` default it is optional ("automatic"), and
      `auto` (a function of the input) tells which value that stands for;
    * `:select` - one of `options` (`[{label, value}]`, values are strings);
    * `:letter_map` - a map from cipher letters "A".."Z" to plain letters,
      edited as an alphabet grid.
    * `:symbol_map` - a map from any character of the step's input to a
      substitution, edited as a grid of the input's distinct characters.
    * `:permutation` - an order of the input's characters ("2,0,1"),
      edited by dragging the characters as tiles.
  """

  @type field :: %{
          required(:name) => atom(),
          required(:type) =>
            :integer | :string | :select | :letter_map | :symbol_map | :permutation,
          required(:label) => String.t(),
          required(:default) => term(),
          optional(:help) => String.t(),
          optional(:min) => integer(),
          optional(:max) => integer() | (input :: String.t() -> integer()),
          optional(:control) => :range,
          optional(:auto) => (input :: String.t() -> term()),
          optional(:options) => [{String.t(), String.t()}]
        }

  @typedoc """
  A suggested set of parameters: a short `label`, the `params` (atom keys,
  only those it sets: they are merged into the current ones) and the
  `reason` it was suggested, in plain words for the user.
  """
  @type suggestion :: %{label: String.t(), params: map(), reason: String.t()}

  @doc "Identifier stored in the database. Never change it once used."
  @callback type() :: String.t()
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback fields() :: [field()]

  @doc """
  What a cipher can start from when it is the first step: `:text` (the
  cipher text is typed or pasted) and/or `:pictures` (symbols detected in
  pictures; only symbol substitution so far). The first one is the default.
  Defaults to `[:text]`.
  """
  @callback input_kinds() :: [:text | :pictures, ...]

  @doc "Extra validations on top of the field types (receives a changeset)."
  @callback validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()

  @doc "Decodes `text` (the previous step's output) with `params`."
  @callback decode(text :: String.t(), params :: map()) :: String.t()

  @doc """
  Optional: the reverse of `decode/2`, encoding plain `text` with `params`
  (`decode(encode(text))` gives `text` back, letters possibly upcased).
  Ciphers implementing it can be part of an algorithm (`Subcipher.Algorithms`).
  Ciphers whose settings only fit one text (an anagram's order) don't.
  """
  @callback encode(text :: String.t(), params :: map()) :: String.t()

  @doc "Optional one-line explanation of the parameters, e.g. the key alphabet."
  @callback summary(params :: map()) :: String.t() | nil

  @doc """
  Optional: sets of parameters likely to decode `input` (the step's input),
  best first, each with the reason it was suggested. About 5 are shown
  (`Subcipher.Steps.suggestions/3` keeps the first ones and adds a preview
  of the result). `params` are the step's current parameters. Return `[]`
  when nothing can be suggested (e.g. the text is too short).
  """
  @callback suggestions(input :: String.t(), params :: map()) :: [suggestion()]

  @doc """
  Optional: tries to find the settings decoding `input` (e.g. with
  `Subcipher.Solver`). Slower than `suggestions/2`, so it only runs when the
  user asks ("Try to solve"), in the background. Returns one suggestion
  (label, params, reason) or `{:error, message}`.
  """
  @callback solve(input :: String.t(), params :: map()) ::
              {:ok, suggestion()} | {:error, String.t()}

  @doc "Optional: where this cipher is used in Old School RuneScape."
  @callback osrs_usage() :: String.t()

  @optional_callbacks summary: 1, suggestions: 2, solve: 2, osrs_usage: 0, encode: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Subcipher.Steps.Cipher
      alias Subcipher.Steps.Alphabet
      import Ecto.Changeset

      @impl true
      def validate(changeset), do: changeset

      @impl true
      def input_kinds, do: [:text]

      defoverridable validate: 1, input_kinds: 0
    end
  end
end
