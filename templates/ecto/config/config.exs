# Configure your database.
# Read more here: https://hexdocs.pm/ecto/Ecto.html
config :<%= @application_name %>, <%= @module_name %>.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "<%= @application_name %>",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
