defmodule Hexpm.Repository.ReleaseTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.Package
  alias Hexpm.Repository.Release

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    ecto =
      Package.build(user, pkg_meta(%{name: "ecto", description: "Ecto is awesome"}))
      |> Hexpm.Repo.insert!
    postgrex =
      Package.build(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"}))
      |> Hexpm.Repo.insert!
    decimal =
      Package.build(user, pkg_meta(%{name: "decimal", description: "Decimal is awesome, too"}))
      |> Hexpm.Repo.insert!

    %{ecto: ecto, postgrex: postgrex, decimal: decimal}
  end

  test "create release and get", %{ecto: package} do
    package_id = package.id

    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
           Release.build(package, rel_meta(%{version: "0.0.1", app: "ecto"}), "") |> Hexpm.Repo.insert!
    assert %Release{package_id: ^package_id, version: %Version{major: 0, minor: 0, patch: 1}} =
           Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1")

    Release.build(package, rel_meta(%{version: "0.0.2", app: "ecto"}), "") |> Hexpm.Repo.insert!
    assert [%Release{version: %Version{major: 0, minor: 0, patch: 2}},
            %Release{version: %Version{major: 0, minor: 0, patch: 1}}] =
           Release.all(package) |> Hexpm.Repo.all |> Release.sort
  end

  test "create release with deps", %{ecto: ecto, postgrex: postgrex, decimal: decimal} do
    Release.build(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> Hexpm.Repo.insert!
    Release.build(decimal, rel_meta(%{version: "0.0.2", app: "decimal"}), "") |> Hexpm.Repo.insert!

    meta = rel_meta(%{requirements: [%{name: "decimal", app: "decimal", requirement: "~> 0.0.1", optional: false}],
                      app: "postgrex", version: "0.0.1"})
    Release.build(postgrex, meta, "") |> Hexpm.Repo.insert!

    meta = rel_meta(%{requirements: [%{name: "decimal", app: "decimal", requirement: "~> 0.0.2", optional: false}, %{name: "postgrex", app: "postgrex", requirement: "== 0.0.1", optional: false}],
                      app: "ecto", version: "0.0.1"})
    Release.build(ecto, meta, "") |> Hexpm.Repo.insert!

    postgrex_id = postgrex.id
    decimal_id = decimal.id

    release = Hexpm.Repo.get_by!(assoc(ecto, :releases), version: "0.0.1")
              |> Hexpm.Repo.preload(:requirements)
    assert [%{dependency_id: ^decimal_id, app: "decimal", requirement: "~> 0.0.2", optional: false},
            %{dependency_id: ^postgrex_id, app: "postgrex", requirement: "== 0.0.1", optional: false}] =
           release.requirements
  end

  test "validate release", %{ecto: ecto, decimal: decimal} do
    Release.build(decimal, rel_meta(%{version: "0.1.0", app: "decimal", requirements: []}), "")
    |> Hexpm.Repo.insert!

    reqs = [%{name: "decimal", app: "decimal", requirement: "~> 0.1", optional: false}]
    Release.build(ecto, rel_meta(%{version: "0.1.0", app: "ecto", requirements: reqs}), "")
    |> Hexpm.Repo.insert!

    meta = %{"version" => "0.1.0", "requirements" => [], "build_tools" => ["mix"]}
    assert %{meta: %{app: [{"can't be blank", _}]}} =
           Release.build(decimal, %{"meta" => meta}, "")
           |> extract_errors

    meta = %{"app" => "decimal", "version" => "0.1.0", "requirements" => []}
    assert %{meta: %{build_tools: [{"can't be blank", _}]}} =
           Release.build(decimal, %{"meta" => meta}, "")
           |> extract_errors

    meta = %{"app" => "decimal", "version" => "0.1.0", "requirements" => [], "build_tools" => []}
    assert %{meta: %{build_tools: [{"can't be blank", _}]}} =
           Release.build(decimal, %{"meta" => meta}, "")
           |> extract_errors

    meta = %{"app" => "decimal", "version" => "0.1.0", "requirements" => [], "build_tools" => ["mix"], "elixir" => "== == 0.0.1"}
    assert %{meta: %{elixir: [{"invalid requirement: \"== == 0.0.1\"", _}]}} =
           Release.build(decimal, %{"meta" => meta}, "")
           |> extract_errors

    assert %{version: [{"is invalid", _}]} =
           Release.build(ecto, rel_meta(%{version: "0.1", app: "ecto"}), "")
           |> extract_errors

    reqs = [%{name: "decimal", app: "decimal", requirement: "~> fail", optional: false}]
    assert %{requirements: [%{requirement: [{"invalid requirement: \"~> fail\"", []}]}]} =
           Release.build(ecto, rel_meta(%{version: "0.1.1", app: "ecto", requirements: reqs}), "")
           |> extract_errors

    reqs = [%{name: "decimal", app: "decimal", requirement: "~> 1.0", optional: false}]
    assert %{requirements: [%{requirement: [{"Failed to use \"decimal\" because\n  mix.exs specifies ~> 1.0\n", []}]}]} =
           Release.build(ecto, rel_meta(%{version: "0.1.1", app: "ecto", requirements: reqs}), "")
           |> extract_errors
  end

  test "ensure unique build tools", %{decimal: decimal} do
    changeset = Release.build(decimal, rel_meta(%{version: "0.1.0", app: "decimal", build_tools: ["mix", "make", "make"]}), "")
    assert changeset.changes.meta.changes.build_tools == ["mix", "make"]
  end

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn err -> err end)
  end

  test "release version is unique", %{ecto: ecto, postgrex: postgrex} do
    Release.build(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "") |> Hexpm.Repo.insert!
    Release.build(postgrex, rel_meta(%{version: "0.0.1", app: "postgrex"}), "") |> Hexpm.Repo.insert!

    assert {:error, %{errors: [version: {"has already been published", []}]}} =
           Release.build(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")
           |> Hexpm.Repo.insert
  end

  test "update release", %{decimal: decimal, postgrex: postgrex} do
    Release.build(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> Hexpm.Repo.insert!
    reqs = [%{name: "decimal", app: "decimal", requirement: "~> 0.0.1", optional: false}]
    release = Release.build(postgrex, rel_meta(%{version: "0.0.1", app: "postgrex", requirements: reqs}), "") |> Hexpm.Repo.insert!

    params = params(%{app: "postgrex", requirements: [%{name: "decimal", app: "decimal", requirement: ">= 0.0.1", optional: false}]})
    Release.update(release, params, "") |> Hexpm.Repo.update!

    decimal_id = decimal.id

    release = Hexpm.Repo.get_by!(assoc(postgrex, :releases), version: "0.0.1")
              |> Hexpm.Repo.preload(:requirements)
    assert [%{dependency_id: ^decimal_id, app: "decimal", requirement: ">= 0.0.1", optional: false}] =
           release.requirements
  end

  test "delete release", %{decimal: decimal, postgrex: postgrex} do
    release = Release.build(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> Hexpm.Repo.insert!
    Release.delete(release) |> Hexpm.Repo.delete!
    refute Hexpm.Repo.get_by(assoc(postgrex, :releases), version: "0.0.1")
  end
end
