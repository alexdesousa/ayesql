defmodule AyeSQL.MixProject do
  use Mix.Project

  @version "1.0.0"
  @name "AyeSQL"
  @description "Library for using raw SQL"
  @app :ayesql
  @root "https://github.com/alexdesousa/ayesql"

  def project do
    [
      name: @name,
      app: @app,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ],
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  #############
  # Application

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto, "~> 3.7", optional: true},
      {:ecto_sql, "~> 3.7", optional: true},
      {:postgrex, ">= 0.0.0", optional: true},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.14", only: :test, runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ecto, :ecto_sql, :postgrex],
      plt_file: {:no_warn, "priv/plts/#{@app}.plt"}
    ]
  end

  #########
  # Package

  defp package do
    [
      description: @description,
      files: [
        "src/ayesql_lexer.xrl",
        "src/ayesql_parser.yrl",
        "lib",
        "mix.exs",
        "LICENSE",
        "README.md",
        "CHANGELOG.md"
      ],
      maintainers: ["Alexander de Sousa"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "#{@root}/blob/master/CHANGELOG.md",
        "Github" => @root
      }
    ]
  end

  ###############
  # Documentation

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      source_url: @root,
      source_ref: "v#{@version}",
      groups_for_modules: groups_for_modules()
    ]
  end

  defp groups_for_modules do
    [
      AyeSQL: [
        AyeSQL
      ],
      "AyeSQL Interpreter": [
        AyeSQL.Core,
        AyeSQL.Query,
        AyeSQL.Error
      ],
      "AyeSQL Compiler": [
        AyeSQL.Compiler,
        AyeSQL.Lexer,
        AyeSQL.AST,
        AyeSQL.AST.Context
      ],
      "AyeSQL runners": [
        AyeSQL.Runner,
        AyeSQL.Runner.Ecto,
        AyeSQL.Runner.Postgrex
      ]
    ]
  end
end
