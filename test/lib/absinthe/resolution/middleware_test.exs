defmodule Absinthe.MiddlewareTest do
  use Absinthe.Case, async: true

  defmodule Auth do
    def call(res, _) do
      case res.context do
        %{current_user: _} ->
          res
        _ ->
          res
          |> Absinthe.Resolution.put_result({:error, "unauthorized"})
      end
    end
  end

  defmodule Schema do
    use Absinthe.Schema

    alias Absinthe.MiddlewareTest

    def middleware(middleware, field, object = %Absinthe.Type.Object{identifier: :secret_object}) do
      fun = &auth/2

      middleware = Absinthe.Schema.ensure_middleware(middleware, field, object)

      [fun | middleware]
    end
    def middleware(middleware, _field, _) do
      middleware
    end

    def auth(res, _) do
      case res.context do
        %{current_user: _} ->
          res
        _ ->
          res
          |> Absinthe.Resolution.put_result({:error, "unauthorized"})
      end
    end

    query do
      field :authenticated, :user do
        middleware MiddlewareTest.Auth

        resolve fn _, _, _ ->
          {:ok, %{name: "bob"}}
        end
      end

      field :public, :user do
        resolve fn _, _, _ ->
          {:ok, %{name: "bob", email: "secret"}}
        end
      end

      field :returns_private_object, :secret_object do
        resolve fn _, _, _ ->
          {:ok, %{key: "value"}}
        end
      end

      field :from_context, :string do
        middleware fn res, _ ->
          %{res | context: %{value: "yooooo"}}
        end

        resolve fn _, %{context: context} ->
          {:ok, context.value}
        end
      end

      field :path, :path do
        resolve fn _, _ -> {:ok, %{}} end
      end
    end

    object :path do
      field :path, :path, resolve: fn _, _ -> {:ok, %{}} end
      field :result, list_of(:string) do
        resolve fn _, info ->
          {:ok, Absinthe.Resolution.path_string(info)}
        end
      end
    end

    # keys in this object are made secret via the def middleware callback
    object :secret_object do
      field :key, :string
      field :key2, :string
    end

    object :user do
      field :email, :string do
        middleware MiddlewareTest.Auth
        middleware Absinthe.Middleware.MapGet, :email
        middleware fn res, _ ->
          # no-op, mostly making sure this form works
          res
        end
      end
      field :name, :string
    end
  end

  test "fails with authorization error when no current user" do
    doc = """
    {authenticated { name }}
    """
    assert {:ok, %{errors: errors}} = Absinthe.run(doc, __MODULE__.Schema)
    assert [%{locations: [%{column: 0, line: 1}], message: "In field \"authenticated\": unauthorized"}] == errors
  end

  test "email fails with authorization error when no current user" do
    doc = """
    {public { name email }}
    """
    assert {:ok, %{errors: errors}} = Absinthe.run(doc, __MODULE__.Schema)
    assert [%{locations: [%{column: 0, line: 1}], message: "In field \"email\": unauthorized"}] == errors
  end

  test "email works when current user" do
    doc = """
    {public { name email }}
    """
    assert {:ok, %{data: data}} = Absinthe.run(doc, __MODULE__.Schema, context: %{current_user: %{}})
    assert %{"public" => %{"email" => "secret", "name" => "bob"}} == data
  end

  test "secret object cant be accessed without a current user" do
    doc = """
    {returnsPrivateObject { key }}
    """
    assert {:ok, %{errors: errors}} = Absinthe.run(doc, __MODULE__.Schema)
    assert [%{locations: [%{column: 0, line: 1}],
               message: "In field \"key\": unauthorized"}] == errors
  end

  test "it can modify the context" do
    doc = """
    {fromContext}
    """
    assert {:ok, %{data: data}} = Absinthe.run(doc, __MODULE__.Schema, context: %{current_user: %{}})
    assert %{"fromContext" => "yooooo"} == data
  end

  test "it gets the path of the current field" do
    doc = """
    {foo: path { bar: path { result }}}
    """
    assert {:ok, %{data: data}} = Absinthe.run(doc, __MODULE__.Schema, context: %{current_user: %{}})
    assert %{"foo" => %{"bar" => %{"result" => ["result", "bar", "foo", "RootQueryType"]}}} == data
  end
end
