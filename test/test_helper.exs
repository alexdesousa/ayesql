ExUnit.start()

Application.ensure_all_started(:mox)

Mox.defmock(Mock.Postgrex, for: AyeSQL.PostgrexBehaviour)
Mox.defmock(Mock.Ecto, for: AyeSQL.EctoBehaviour)

Application.put_env(:ayesql, :postgrex_module, Mock.Postgrex)
Application.put_env(:ayesql, :ecto_module, Mock.Ecto)
