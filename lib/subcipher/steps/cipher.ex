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

    * `:integer`, `:string` - a plain input;
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
          optional(:max) => integer(),
          optional(:options) => [{String.t(), String.t()}]
        }

  @typedoc "A suggested set of parameters, e.g. the most likely Caesar shifts."
  @type candidate :: %{label: String.t(), params: map(), preview: String.t()}

  @doc "Identifier stored in the database. Never change it once used."
  @callback type() :: String.t()
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback fields() :: [field()]

  @doc "Extra validations on top of the field types (receives a changeset)."
  @callback validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()

  @doc "Decodes `text` (the previous step's output) with `params`."
  @callback decode(text :: String.t(), params :: map()) :: String.t()

  @doc "Optional one-line explanation of the parameters, e.g. the key alphabet."
  @callback summary(params :: map()) :: String.t() | nil

  @doc "Optional parameter suggestions for `input`, best first."
  @callback candidates(input :: String.t(), params :: map()) :: [candidate()]

  @doc "Optional: where this cipher is used in Old School RuneScape."
  @callback osrs_usage() :: String.t()

  @optional_callbacks summary: 1, candidates: 2, osrs_usage: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Subcipher.Steps.Cipher
      alias Subcipher.Steps.Alphabet
      import Ecto.Changeset

      @impl true
      def validate(changeset), do: changeset

      defoverridable validate: 1
    end
  end
end
