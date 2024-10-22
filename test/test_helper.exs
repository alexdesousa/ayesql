ExUnit.start()

Application.ensure_all_started(:mox)

Mox.defmock(Mock.Postgrex, for: AyeSQL.PostgrexBehaviour)
Mox.defmock(Mock.Ecto, for: AyeSQL.EctoBehaviour)
Mox.defmock(Mock.Duckdbex, for: AyeSQL.DuckdbexBehaviour)

Application.put_env(:ayesql, :postgrex_module, Mock.Postgrex)
Application.put_env(:ayesql, :ecto_module, Mock.Ecto)
Application.put_env(:ayesql, :duckdbex_module, Mock.Duckdbex)
