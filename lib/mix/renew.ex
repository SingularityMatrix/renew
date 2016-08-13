defmodule Mix.Tasks.Renew do
  use Mix.Task

  import Mix.Generator

  @shortdoc "Creates a new Elixir project based on Nebo #15 requirements."

  @moduledoc """
  Creates a new Elixir project.
  It expects the path of the project as argument.

      mix new PATH [--sup] [--module MODULE] [--app APP] [--umbrella]

  A project at the given PATH  will be created. The
  application name and module name will be retrieved
  from the path, unless `--module` or `--app` is given.

  A `--sup` option can be given to generate an OTP application
  skeleton including a supervision tree. Normally an app is
  generated without a supervisor and without the app callback.

  An `--umbrella` option can be given to generate an
  umbrella project.

  An `--app` option can be given in order to
  name the OTP application for the project.

  A `--module` option can be given in order
  to name the modules in the generated code skeleton.

  ## Examples

      mix new hello_world

  Is equivalent to:

      mix new hello_world --module HelloWorld

  To generate an app with supervisor and application callback:

      mix new hello_world --sup

  """

  @switches [sup: :boolean, umbrella: :boolean, app: :string, module: :string]

  @spec run(OptionParser.argv) :: :ok
  def run(argv) do
    {opts, argv} = OptionParser.parse!(argv, strict: @switches)

    case argv do
      [] ->
        Mix.raise "Expected PATH to be given, please use \"mix new PATH\""
      [path | _] ->
        app = opts[:app] || Path.basename(Path.expand(path))
        check_application_name!(app, !!opts[:app])
        mod = opts[:module] || Macro.camelize(app)
        check_mod_name_validity!(mod)
        check_mod_name_availability!(mod)
        File.mkdir_p!(path)

        File.cd! path, fn ->
          if opts[:umbrella] do
            generate_umbrella(app, mod, path, opts)
          else
            generate(app, mod, path, opts)
          end
        end
    end
  end

  defp generate(app, mod, path, opts) do
    assigns = [app: app, mod: mod, otp_app: otp_app(mod, !!opts[:sup]),
               version: get_version(System.version), minor_version: get_minor_version(System.version)]

    create_file "README.md",     readme_template(assigns)
    create_file "LICENSE.md",    license_text()
    create_file ".gitignore",    gitignore_text()
    create_file ".dockerignore", dockerignore_text()
    create_file "Dockerfile",    dockerfile_template(assigns)
    create_file ".env",          dotenv_text()

    if in_umbrella?() do
      create_file "mix.exs", mixfile_apps_template(assigns)
    else
      create_file "mix.exs", mixfile_template(assigns)
    end

    create_directory "config"
    create_file "config/config.exs", config_template(assigns)
    create_file "config/.credo.exs", credo_text()
    create_file "config/dogma.exs", dogma_text()
    create_file "coveralls.json", coveralls_text()

    create_file ".travis.yml", travis_text()

    create_directory "lib"

    create_directory "bin"
    create_file "bin/build.sh", build_script_text()
    System.cmd "chmod", ["+x", "bin/build.sh"]

    if opts[:sup] do
      create_file "lib/#{app}.ex", lib_sup_template(assigns)
    else
      create_file "lib/#{app}.ex", lib_template(assigns)
    end

    create_directory "rel"
    create_file "rel/config.exs", release_config_template(assigns)

    create_directory "test"
    create_file "test/test_helper.exs", test_helper_template(assigns)
    create_file "test/#{app}_test.exs", test_template(assigns)

    """

    Your Mix project was created successfully.
    You can use "mix" to compile it, test it, and more:

        cd #{path}
        mix test

    Run "mix help" for more commands.
    """
    |> String.trim_trailing
    |> Mix.shell.info
  end

  defp otp_app(_mod, false) do
    "    [applications: [:logger]]"
  end

  defp otp_app(mod, true) do
    "    [applications: [:logger],\n     mod: {#{mod}, []}]"
  end

  defp generate_umbrella(_app, mod, path, _opts) do
    assigns = [app: nil, mod: mod]

    create_file ".gitignore", gitignore_text()
    create_file "README.md", readme_template(assigns)
    create_file "mix.exs", mixfile_umbrella_template(assigns)

    create_directory "apps"

    create_directory "config"
    create_file "config/config.exs", config_umbrella_template(assigns)

    """

    Your umbrella project was created successfully.
    Inside your project, you will find an apps/ directory
    where you can create and host many apps:

        cd #{path}
        cd apps
        mix new my_app

    Commands like "mix compile" and "mix test" when executed
    in the umbrella project root will automatically run
    for each application in the apps/ directory.
    """
    |> String.trim_trailing
    |> Mix.shell.info
  end

  defp check_application_name!(name, from_app_flag) do
    unless name =~ ~r/^[a-z][\w_]*$/ do
      Mix.raise "Application name must start with a letter and have only lowercase " <>
                "letters, numbers and underscore, got: #{inspect name}" <>
                (if !from_app_flag do
                  ". The application name is inferred from the path, if you'd like to " <>
                  "explicitly name the application then use the \"--app APP\" option."
                else
                  ""
                end)
    end
  end

  defp check_mod_name_validity!(name) do
    unless name =~ ~r/^[A-Z]\w*(\.[A-Z]\w*)*$/ do
      Mix.raise "Module name must be a valid Elixir alias (for example: Foo.Bar), got: #{inspect name}"
    end
  end

  defp check_mod_name_availability!(name) do
    name = Module.concat(Elixir, name)
    if Code.ensure_loaded?(name) do
      Mix.raise "Module name #{inspect name} is already taken, please choose another name"
    end
  end

  defp get_minor_version(version) do
    {:ok, version} = Version.parse(version)
    "#{version.major}.#{version.minor}.#{version.patch}"
  end

  defp get_version(version) do
    {:ok, version} = Version.parse(version)
    "#{version.major}.#{version.minor}" <>
      case version.pre do
        [h | _] -> "-#{h}"
        []      -> ""
      end
  end

  defp in_umbrella? do
    apps = Path.dirname(File.cwd!)

    try do
      Mix.Project.in_project(:umbrella_check, "../..", fn _ ->
        path = Mix.Project.config[:apps_path]
        path && Path.expand(path) == apps
      end)
    catch
      _, _ -> false
    end
  end

  embed_template :readme, """
  # <%= @mod %>

  **TODO: Add description**
  <%= if @app do %>
  ## Installation

  If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

    1. Add `<%= @app %>` to your list of dependencies in `mix.exs`:

      ```elixir
      def deps do
        [{:<%= @app %>, "~> 0.1.0"}]
      end
      ```

    2. Ensure `<%= @app %>` is started before your application:

      ```elixir
      def application do
        [applications: [:<%= @app %>]]
      end
      ```

  If [published on HexDocs](https://hex.pm/docs/tasks#hex_docs), the docs can
  be found at [https://hexdocs.pm/<%= @app %>](https://hexdocs.pm/<%= @app %>)
  <% end %>
  """

  embed_text :credo, """
  %{
    configs: [
      %{
        name: "default",
        files: %{
          included: ["lib/", "www/"]
        },
        checks: [
          {Credo.Check.Design.TagTODO, exit_status: 0}
        ]
      }
    ]
  }
  """

  embed_text :dogma, """
  use Mix.Config
  alias Dogma.Rule

  config :dogma,
    rule_set: Dogma.RuleSet.All,
    override: [
      %Rule.LineLength{ max_length: 120 },
      %Rule.TakenName{ enabled: false }, # TODO: https://github.com/lpil/dogma/issues/201
      %Rule.InfixOperatorPadding{ enabled: false }
    ]
  """

  embed_text :travis, """
  language: elixir
  elixir:
    - 1.3.0
  otp_release:
    - 18.0
    - 19.0
  env:
    - MIX_ENV=test
  script:
    - "mix deps.get"
    - "mix test --trace"
    - "mix coveralls.travis"
    - "mix credo"
    - "mix dogma"
  """

  embed_text :coveralls, """
  {}
  """

  embed_text :license, """
  **TODO: Add license**
  """

  embed_text :gitignore, """
  # The directory Mix will write compiled artifacts to.
  /_build

  # If you run "mix test --cover", coverage assets end up here.
  /cover

  # The directory Mix downloads your dependencies sources to.
  /deps

  # Where 3rd-party dependencies like ExDoc output generated docs.
  /doc

  # If the VM crashes, it generates a dump, let's ignore it too.
  erl_crash.dump

  # Also ignore archive artifacts (built via "mix archive.build").
  *.ez

  # Don't commit benchmark snapshots
  bench/snapshots

  # Don't commit editor configs
  .idea
  *.iws
  /out/
  atlassian-ide-plugin.xml
  *.tmlanguage.cache
  *.tmPreferences.cache
  *.stTheme.cache
  *.sublime-workspace
  sftp-config.json
  GitHub.sublime-settings
  .tags
  .tags_sorted_by_file
  .vagrant
  .DS_Store

  # Ignore released binaries
  rel/*/
  """

  embed_text :dockerignore, """
  # The directory Mix will write compiled artifacts to.
  /_build

  # The directory Mix downloads your dependencies sources to.
  /deps

  # If you run "mix test --cover", coverage assets end up here.
  /cover

  # Ignore released binaries
  /rel/*/

  # If the VM crashes, it generates a dump, let's ignore it too.
  erl_crash.dump

  # Ignore any node modules, as they should be fetched within container
  /node_modules

  # Ignore static files
  /priv/static/*

  # Ignore Phoenix uploads in dev env
  /uploads/files/*

  # Ignore git artifacts
  .git
  .gitignore

  # Ignore Docker artifacts
  Dockerfile
  .dockerignore

  # Ignore markdown description
  README.md
  LICENSE.md
  """

  embed_text :build_script, """
  PROJECT_DIR=$(git rev-parse --show-toplevel)
  PROJECT_NAME=${PROJECT_DIR##*/}

  echo "[I] Building a Docker container '${PROJECT_NAME}' from path '${PROJECT_DIR}'.."

  docker build -t "${PROJECT_NAME}" -f "${PROJECT_DIR}/Dockerfile" "${PROJECT_DIR}"
  """

  embed_text :dotenv, """
  # Define your environment variables here in a FOO="bar" format.
  #
  # Later you can use them to start a Docker container:
  # $ docker run --env-file ./.env [rest]
  #
  # This variables will replace any ${VAR_NAME} in your config (eg. config/confix.exs) files.
  """

  embed_template :dockerfile, """
  # Set the Docker image you want to base your image off.
  # I chose this one because it has Elixir preinstalled.
  FROM trenpixster/elixir:<%= @minor_version %>

  # Maintainers
  MAINTAINER Nebo#15 @nebo15

  # Install other stable dependencies that don't change often

  # Compile app
  RUN mkdir /app
  WORKDIR /app

  # Install Elixir Deps
  ADD mix.* ./
  RUN MIX_ENV=prod mix local.rebar --force
  RUN MIX_ENV=prod mix local.hex --force
  RUN MIX_ENV=prod mix deps.get

  # Generate release
  ADD . .
  RUN MIX_ENV=prod mix release --env=prod

  # Clean sources
  RUN mv rel ../rel
  RUN rm -rf ./*
  WORKDIR ../rel

  # Allow to read ENV vars for mix configs
  ENV REPLACE_OS_VARS=true

  # Set entrypoint to run app
  ENTRYPOINT ["<%= @app %>/bin/<%= @app %>", "start"]

  # Runtime config

  # Compile assets
  # RUN MIX_ENV=prod mix phoenix.digest

  # Exposes this port from the docker container to the host machine
  # EXPOSE 4000

  # The command to run when this image starts up
  # CMD MIX_ENV=prod mix ecto.migrate && \
  #  MIX_ENV=prod mix phoenix.server
  """

  embed_template :release_config, """
  use Mix.Releases.Config,
    default_release: :default,
    default_environment: :prod

  environment :prod do
    set dev_mode: false
    set include_erts: false
    set include_src: false
  end

  release :<%= @app %> do
    set version: current_version(:<%= @app %>)
  end
  """

  embed_template :mixfile, """
  defmodule <%= @mod %>.Mixfile do
    use Mix.Project

    @version "0.1.0"

    def project do
      [app: :<%= @app %>,
       description: "Add description to your package.",
       package: package,
       version: @version,
       elixir: "~> <%= @version %>",
       build_embedded: Mix.env == :prod,
       start_permanent: Mix.env == :prod,
       deps: deps(),
       test_coverage: [tool: ExCoveralls],
       preferred_cli_env: [coveralls: :test],
       docs: [source_ref: "v#\{@version\}", main: "readme", extras: ["README.md"]]]
    end

    # Configuration for the OTP application
    #
    # Type "mix help compile.app" for more information
    def application do
  <%= @otp_app %>
    end

    # Dependencies can be Hex packages:
    #
    #   {:mydep, "~> 0.3.0"}
    #
    # Or git/path repositories:
    #
    #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
    #
    # Type "mix help deps" for more examples and options
    defp deps do
      [{:distillery, "~> 0.9"},
       {:benchfella, "~> 0.3", only: [:dev, :test]},
       {:ex_doc, ">= 0.0.0", only: [:dev, :test]},
       {:excoveralls, "~> 0.5", only: [:dev, :test]},
       {:dogma, "> 0.1.0", only: [:dev, :test]},
       {:credo, ">= 0.4.8", only: [:dev, :test]}]
    end

    defp package do
      [contributors: ["Nebo #15"],
       maintainers: ["Nebo #15"],
       licenses: ["LISENSE.md"],
       links: %{github: "https://github.com/Nebo15/<%= @app %>"},
       files: ~w(lib LICENSE.md mix.exs README.md)]
    end
  end
  """

  embed_template :mixfile_apps, """
  defmodule <%= @mod %>.Mixfile do
    use Mix.Project

    def project do
      [app: :<%= @app %>,
       version: "0.1.0",
       build_path: "../../_build",
       config_path: "../../config/config.exs",
       deps_path: "../../deps",
       lockfile: "../../mix.lock",
       elixir: "~> <%= @version %>",
       build_embedded: Mix.env == :prod,
       start_permanent: Mix.env == :prod,
       deps: deps()]
    end

    # Configuration for the OTP application
    #
    # Type "mix help compile.app" for more information
    def application do
  <%= @otp_app %>
    end

    # Dependencies can be Hex packages:
    #
    #   {:mydep, "~> 0.3.0"}
    #
    # Or git/path repositories:
    #
    #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
    #
    # To depend on another app inside the umbrella:
    #
    #   {:myapp, in_umbrella: true}
    #
    # Type "mix help deps" for more examples and options
    defp deps do
      []
    end
  end
  """

  embed_template :mixfile_umbrella, """
  defmodule <%= @mod %>.Mixfile do
    use Mix.Project

    def project do
      [apps_path: "apps",
       build_embedded: Mix.env == :prod,
       start_permanent: Mix.env == :prod,
       deps: deps()]
    end

    # Dependencies can be Hex packages:
    #
    #   {:mydep, "~> 0.3.0"}
    #
    # Or git/path repositories:
    #
    #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
    #
    # Type "mix help deps" for more examples and options.
    #
    # Dependencies listed here are available only for this project
    # and cannot be accessed from applications inside the apps folder
    defp deps do
      [{:distillery, "~> 0.9"},
       {:benchfella, "~> 0.3", only: [:dev, :test]},
       {:ex_doc, ">= 0.0.0", only: [:dev, :test]},
       {:excoveralls, "~> 0.5", only: [:dev, :test]},
       {:dogma, "> 0.1.0", only: [:dev, :test]},
       {:credo, ">= 0.4.8", only: [:dev, :test]}]
    end
  end
  """

  embed_template :config, ~S"""
  # This file is responsible for configuring your application
  # and its dependencies with the aid of the Mix.Config module.
  use Mix.Config

  # This configuration is loaded before any dependency and is restricted
  # to this project. If another project depends on this project, this
  # file won't be loaded nor affect the parent project. For this reason,
  # if you want to provide default values for your application for
  # 3rd-party users, it should be done in your "mix.exs" file.

  # You can configure for your application as:
  #
  #     config :<%= @app %>, key: :value
  #
  # And access this configuration in your application as:
  #
  #     Application.get_env(:<%= @app %>, :key)
  #
  # Or configure a 3rd-party app:
  #
  #     config :logger, level: :info
  #
  # Or read environment variables in runtime (!) as:
  #
  #     :var_name, "${ENV_VAR_NAME}"

  # It is also possible to import configuration files, relative to this
  # directory. For example, you can emulate configuration per environment
  # by uncommenting the line below and defining dev.exs, test.exs and such.
  # Configuration from the imported file will override the ones defined
  # here (which is why it is important to import them last).
  #
  #     import_config "#{Mix.env}.exs"
  """

  embed_template :config_umbrella, ~S"""
  # This file is responsible for configuring your application
  # and its dependencies with the aid of the Mix.Config module.
  use Mix.Config

  # By default, the umbrella project as well as each child
  # application will require this configuration file, ensuring
  # they all use the same configuration. While one could
  # configure all applications here, we prefer to delegate
  # back to each application for organization purposes.
  import_config "../apps/*/config/config.exs"

  # Sample configuration (overrides the imported configuration above):
  #
  #     config :logger, :console,
  #       level: :info,
  #       format: "$date $time [$level] $metadata$message\n",
  #       metadata: [:user_id]
  """

  embed_template :lib, """
  defmodule <%= @mod %> do
  end
  """

  embed_template :lib_sup, """
  defmodule <%= @mod %> do
    use Application

    # See http://elixir-lang.org/docs/stable/elixir/Application.html
    # for more information on OTP Applications
    def start(_type, _args) do
      import Supervisor.Spec, warn: false

      # Define workers and child supervisors to be supervised
      children = [
        # Starts a worker by calling: <%= @mod %>.Worker.start_link(arg1, arg2, arg3)
        # worker(<%= @mod %>.Worker, [arg1, arg2, arg3]),
      ]

      # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
      # for other strategies and supported options
      opts = [strategy: :one_for_one, name: <%= @mod %>.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  """

  embed_template :test, """
  defmodule <%= @mod %>Test do
    use ExUnit.Case
    doctest <%= @mod %>

    test "the truth" do
      assert 1 + 1 == 2
    end
  end
  """

  embed_template :test_helper, """
  ExUnit.start()
  """
end