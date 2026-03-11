defmodule Apothecary do
  @moduledoc """
  Apothecary keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc "Whether platform mode is active (PLATFORM_DOMAIN env var set)."
  def platform_mode?, do: Application.get_env(:apothecary, :platform_mode, false)

  @doc "The configured platform domain (e.g. `myapp.example.com`)."
  def platform_domain, do: Application.get_env(:apothecary, :platform_domain)
end
