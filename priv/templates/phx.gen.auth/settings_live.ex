defmodule <%= inspect context.web_module %>.<%= inspect Module.concat(schema.web_namespace, schema.alias) %>Live.Settings do
  use <%= inspect context.web_module %>, :live_view

  alias <%= inspect context.module %>

  def render(assigns) do
    ~H"""
    <.header class="text-center">
      Account Settings
      <:subtitle>Manage your account email address and password settings</:subtitle>
    </.header>

    <div class="space-y-12 divide-y">
      <div>
        <.simple_form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <.input
            field={@email_form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            required
          />
          <.input
            field={@email_form[:current_password]}
            name="current_password"
            id="current_password_for_email"
            type="password"
            label="Current password"
            value={@email_form_current_password}
            autocomplete="current-password"
            required
          />
          <:actions>
            <.button phx-disable-with="Changing...">Change Email</.button>
          </:actions>
        </.simple_form>
      </div>
      <div>
        <.simple_form
          for={@password_form}
          id="password_form"
          action={~p"<%= schema.route_prefix %>/log-in?_action=password-updated"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden_<%= schema.singular %>_email"
            autocomplete="username"
            value={@current_email}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
          />
          <.input
            field={@password_form[:current_password]}
            name="current_password"
            type="password"
            label="Current password"
            id="current_password_for_password"
            value={@current_password}
            autocomplete="current-password"
            required
          />
          <:actions>
            <.button phx-disable-with="Changing...">Change Password</.button>
          </:actions>
        </.simple_form>
      </div><%= if totp? do %>
      <div>
        <%%= if @current_<%= schema.singular %>.totp_secret do %>
          <.simple_form for={@totp_form} id="totp_form" phx-submit="disable_totp">
            <.header class="text-center">
              Turn off verification in two steps
              <:subtitle>Enter the code provided by your 2FA app</:subtitle>
            </.header>

            <.input field={@totp_form[:code]} type="text" maxlength="6" label="Code" required />

            <.input
              field={@totp_form[:current_password]}
              type="password"
              label="Current password"
              required
            />

            <:actions>
              <.button phx-disable-with="Turning off...">Turn off</.button>
            </:actions>
          </.simple_form>
        <%% else %>
          <.simple_form for={@totp_form} id="totp_form" phx-submit="enable_totp">
            <.header class="text-center">
              Turn on verification in two steps
              <:subtitle>Scan the QR code below with your favorite 2FA app</:subtitle>
            </.header>

            <div class="bg-white max-w-[200px] mx-auto aspect-square">
              <%%= @otp_url
              |> EQRCode.encode()
              |> EQRCode.svg(viewbox: true)
              |> raw() %>
            </div>

            <.input
              field={@totp_form[:code]}
              type="text"
              maxlength="6"
              label="Enter the code provided by your 2FA app"
              required
            />

            <:actions>
              <.button phx-disable-with="Turning on...">Turn on</.button>
            </:actions>
          </.simple_form>
        <%% end %>
      </div><% end %>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case <%= inspect context.alias %>.update_<%= schema.singular %>_email(socket.assigns.current_<%= schema.singular %>, token) do
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"<%= schema.route_prefix %>/settings")}
  end

  def mount(_params, _session, socket) do
    <%= schema.singular %> = socket.assigns.current_<%= schema.singular %>
    email_changeset = <%= inspect context.alias %>.change_<%= schema.singular %>_email(<%= schema.singular %>)
    password_changeset = <%= inspect context.alias %>.change_<%= schema.singular %>_password(<%= schema.singular %>)<%= if totp? do %>
    totp_changeset = <%= inspect context.alias %>.change_<%= schema.singular %>_totp(<%= schema.singular %>)

    totp_secret = <%= schema.singular %>.totp_secret || NimbleTOTP.secret()
    otp_url = NimbleTOTP.otpauth_uri("Dummy - #{<%= schema.singular %>.email}", totp_secret, issuer: "Dummy")<% end %>

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, <%= schema.singular %>.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)<%= if totp? do %>
      |> assign(:totp_form, to_form(totp_changeset))
      |> assign(:totp_secret, totp_secret)
      |> assign(:otp_url, otp_url)<% end %>

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "<%= schema.singular %>" => <%= schema.singular %>_params} = params

    email_form =
      socket.assigns.current_<%= schema.singular %>
      |> <%= inspect context.alias %>.change_<%= schema.singular %>_email(<%= schema.singular %>_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "<%= schema.singular %>" => <%= schema.singular %>_params} = params
    <%= schema.singular %> = socket.assigns.current_<%= schema.singular %>

    case <%= inspect context.alias %>.apply_<%= schema.singular %>_email(<%= schema.singular %>, password, <%= schema.singular %>_params) do
      {:ok, applied_<%= schema.singular %>} ->
        <%= inspect context.alias %>.deliver_<%= schema.singular %>_update_email_instructions(
          applied_<%= schema.singular %>,
          <%= schema.singular %>.email,
          &url(~p"<%= schema.route_prefix %>/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "<%= schema.singular %>" => <%= schema.singular %>_params} = params

    password_form =
      socket.assigns.current_<%= schema.singular %>
      |> <%= inspect context.alias %>.change_<%= schema.singular %>_password(<%= schema.singular %>_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "<%= schema.singular %>" => <%= schema.singular %>_params} = params
    <%= schema.singular %> = socket.assigns.current_<%= schema.singular %>

    case <%= inspect context.alias %>.update_<%= schema.singular %>_password(<%= schema.singular %>, password, <%= schema.singular %>_params) do
      {:ok, <%= schema.singular %>} ->
        password_form =
          <%= schema.singular %>
          |> <%= inspect context.alias %>.change_<%= schema.singular %>_password(<%= schema.singular %>_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end<%= if totp? do %>

  def handle_event("enable_totp", %{"<%= schema.singular %>" => <%= schema.singular %>_params}, socket) do
    %{"code" => code} = <%= schema.singular %>_params
    <%= schema.singular %> = socket.assigns.current_<%= schema.singular %>
    secret = socket.assigns.totp_secret

    case <%= inspect context.alias %>.enable_<%= schema.singular %>_totp(<%= schema.singular %>, secret, code) do
      {:ok, <%= schema.singular %>} ->
        info = "2FA enabled successfully."
        changeset = <%= inspect context.alias %>.change_<%= schema.singular %>_totp(<%= schema.singular %>)

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> assign(:current_<%= schema.singular %>, <%= schema.singular %>)
         |> assign(:totp_form, to_form(changeset))}

      {:error, changeset} ->
        {:noreply, assign(socket, :totp_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("disable_totp", %{"<%= schema.singular %>" => <%= schema.singular %>_params}, socket) do
    %{"code" => code, "current_password" => password} = <%= schema.singular %>_params
    <%= schema.singular %> = socket.assigns.current_<%= schema.singular %>

    case <%= inspect context.alias %>.disable_<%= schema.singular %>_totp(<%= schema.singular %>, password, code) do
      {:ok, <%= schema.singular %>} ->
        info = "2FA disabled successfully."
        changeset = <%= inspect context.alias %>.change_<%= schema.singular %>_totp(<%= schema.singular %>)

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> assign(:current_<%= schema.singular %>, <%= schema.singular %>)
         |> assign(:totp_form, to_form(changeset))}

      {:error, changeset} ->
        {:noreply, assign(socket, :totp_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end<% end %>
end
