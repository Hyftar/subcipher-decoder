defmodule Subcipher.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Subcipher.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Subcipher.Accounts.User

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc "Whether the scope's user owns `record` (a puzzle or an algorithm)."
  def owner?(%__MODULE__{user: %{id: id}}, %{user_id: id}) when not is_nil(id), do: true
  def owner?(_scope, _record), do: false

  @doc "Whether `record` can be seen: public, or owned by the scope's user."
  def can_view?(_scope, %{public: true}), do: true
  def can_view?(scope, record), do: owner?(scope, record)
end
