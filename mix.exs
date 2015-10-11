defmodule Exmapper.Mixfile do
  use Mix.Project

  def project do
    [app: :exmapper,
     version: "0.0.2",
     elixir: "~> 1.0.0",
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger, :tzdata]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
        { :timex, "~> 0.19.3", [hex_app: :timex] },
	      { :json, github: "kepit/json" },
        { :mariaex, "~> 0.4.3" },
        { :poolboy, "~> 1.5.1" },
        { :emysql, github: "kepit/emysql" },
    ]
  end
end
