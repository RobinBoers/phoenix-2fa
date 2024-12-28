defmodule <%= inspect schema.module %> do
  use Ecto.Schema
  import Ecto.Changeset

<%= if totp? do %>  alias <%= inspect context.module %><% end %>
<%= if schema.binary_id do %>  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id<% end %>
  schema <%= inspect schema.table %> do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :current_password, :string, virtual: true, redact: true
    <%= if totp? do %>field :totp_secret, EctoBase64, redact: true
    <% end %>field :last_login, :naive_datetime
    field :confirmed_at, <%= inspect schema.timestamp_type %>

    timestamps(<%= if schema.timestamp_type != :naive_datetime, do: "type: #{inspect schema.timestamp_type}" %>)
  end

  @doc """
  A <%= schema.singular %> changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.

    * `:validate_email` - Validates the uniqueness of the email, in case
      you don't want to validate the uniqueness of the email (like when
      using this changeset for validations on a LiveView form before
      submitting the form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(<%= schema.singular %>, attrs, opts \\ []) do
    <%= schema.singular %>
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset<%= if hashing_library.name == :bcrypt do %>
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)<% end %>
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, <%= inspect hashing_library.module %>.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, <%= inspect schema.repo %>)
      |> unique_constraint(:email)
    else
      changeset
    end
  end<%= if totp? do %>

  @doc """
  A <%= schema.singular %> changeset for changing the OTP secret.
  """
  def totp_changeset(<%= schema.singular %>, attrs) do
    cast(<%= schema.singular %>, attrs, [:totp_secret])
  end<% end %>

  @doc """
  A <%= schema.singular %> changeset for marking the last login.
  """
  def login_changeset(<%= schema.singular %>) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(<%= schema.singular %>, last_login: now)
  end<%= if totp? do %>

  @doc """
  Validates whether the provided code is valid for the OTP secret.

  ## Options

    * `:for` - Against which OTP secret to compare the code.
      Can be either `:given` or `:<%= schema.singular %>`. If `:given`, the code will
      be checked against the new OTP secret in the changeset changes. If
      `:<%= schema.singular %>`, the code will be checked against the OTP secret on the <%= schema.singular %>.
      Defaults to `:given`.
  """
  def validate_totp(changeset, code, opts \\ []) do
    secret =
      case Keyword.get(opts, :for, :given) do
        :given -> Map.fetch!(changeset.changes, :totp_secret)
        :<%= schema.singular %> -> changeset.data
      end

    if <%= inspect context.alias %>.valid_<%= schema.singular %>_totp?(secret, code) do
      changeset
    else
      add_error(changeset, :code, "did not match")
    end
  end<% end %>

  @doc """
  A <%= schema.singular %> changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(<%= schema.singular %>, attrs, opts \\ []) do
    <%= schema.singular %>
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A <%= schema.singular %> changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(<%= schema.singular %>, attrs, opts \\ []) do
    <%= schema.singular %>
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(<%= schema.singular %>) do
    <%= case schema.timestamp_type do %>
    <% :naive_datetime -> %>now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    <% :utc_datetime -> %>now = DateTime.utc_now() |> DateTime.truncate(:second)
    <% :utc_datetime_usec -> %>now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    <% end %>change(<%= schema.singular %>, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no <%= schema.singular %> or the <%= schema.singular %> doesn't have a password, we call
  `<%= inspect hashing_library.module %>.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%<%= inspect schema.module %>{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    <%= inspect hashing_library.module %>.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    <%= inspect hashing_library.module %>.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end
end
