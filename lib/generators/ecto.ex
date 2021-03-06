defmodule Renew.Generators.Ecto do
  use Renew.Generator

  load_templates :tpl, [
    {:cp, "ecto/lib/repo.ex",                   "lib/<%= @application_name %>/repo.ex"},
    {:cp, "ecto/priv/repo/seeds.exs",           "priv/repo/seeds.exs"},
    {:mkdir, "ecto/priv/repo/migrations/",      "priv/repo/migrations/"},
    {:mkdir, "ecto/test/unit/models/",          "test/unit/models/"},
    {:cp, "ecto/test/support/model_case.ex",    "test/support/model_case.ex"},
    {:append, "ecto/.env",                      ".env"},
    {:append, "ecto/bin/hooks/pre-start.sh",    "bin/hooks/pre-start.sh"},
    {:cp, "ecto/lib/tasks.ex",                  "lib/<%= @application_name %>/tasks.ex"},
  ]

  load_templates :tpl_postgre, [
    {:cp, "ecto/bin/ci/init-postgres-db.sh",    "bin/ci/init-db.sh"},
  ]

  load_templates :tpl_mysql, [
    {:cp, "ecto/bin/ci/init-mysql-db.sh",    "bin/ci/init-db.sh"},
  ]

  @deps [
    ~S({:ecto, "~> 2.0"}),
  ]

  @apps [
    ~S(:ecto),
  ]

  def apply?(assigns) do
    assigns[:ecto] && !assigns[:umbrella]
  end

  def apply_settings({path, assigns}) do
    {adapter_dep,
     adapter_app,
     {config,
     config_test,
     config_dev,
     config_prod}} = Renew.Generators.Ecto.get_adapter(assigns[:ecto_db],
                                                       String.downcase(assigns[:application_name]),
                                                       assigns[:module_name])

    assigns = assigns
    |> add_project_dependencies(@deps ++ [adapter_dep])
    |> add_project_applications(@apps ++ [adapter_app])
    |> add_config(config)
    |> add_test_config(config_test)
    |> add_dev_config(config_dev)
    |> add_prod_config(config_prod)

    {path, assigns}
  end

  def apply_template({path, %{ecto_db: "postgres"} = assigns}) do
    apply_template @tpl ++ @tpl_postgre, path, assigns

    {path, assigns}
  end

  def apply_template({path, %{ecto_db: "mysql"} = assigns}) do
    apply_template @tpl ++ @tpl_mysql, path, assigns

    {path, assigns}
  end

  def get_adapter("mysql", app, module) do
    {~S({:mariaex, "~> 0.7.7"}),
     ~S(:mariaex),
     db_config(app, module, ~S(Ecto.Adapters.MySQL), "root", "")}
  end

  def get_adapter("postgres", app, module) do
    {~S({:postgrex, "~> 0.11.2"}),
     ~S(:postgrex),
     db_config(app, module, ~S(Ecto.Adapters.Postgres), "postgres", "postgres")}
  end

  def get_adapter(db, _app, _mod) do
    Mix.raise "Unknown database #{inspect db}"
  end

  defp db_config(application_name, module_name, adapter_name, db_user, db_password) do
    main = """
    # Configure your database
    config :#{application_name}, #{module_name}.Repo,
      adapter: #{adapter_name},
      database: "#{application_name}_dev",
      username: "#{db_user}",
      password: "#{db_password}",
      hostname: "localhost"
    """

    test = """
    # Configure your database
    config :#{application_name}, #{module_name}.Repo,
      pool: Ecto.Adapters.SQL.Sandbox,
      database: "#{application_name}_test"
    """

    prod = """
    # Configure your database
    config :#{application_name}, #{module_name}.Repo,
      adapter: #{adapter_name},
      database: "${DB_NAME}",
      username: "${DB_USER}",
      password: "${DB_PASSWORD}",
      hostname: "${DB_HOST}",
      port: "${DB_PORT}"
    """

    {main, test, "", prod}
  end
end
