defmodule HexWeb.PackageTest do
  use HexWeb.ModelCase, async: true

  alias HexWeb.User
  alias HexWeb.Package

  setup do
    %{user: create_user("eric", "eric@mail.com", "ericeric")}
  end

  test "create package and get", %{user: user} do
    user_id = user.id

    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!
    assert [%User{id: ^user_id}] = HexWeb.Repo.get_by(Package, name: "ecto") |> assoc(:owners) |> HexWeb.Repo.all
    assert is_nil(HexWeb.Repo.get_by(Package, name: "postgrex"))
  end

  test "update package", %{user: user} do
    package = Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!

    Package.update(package, %{"meta" => %{"maintainers" => ["eric", "josé"], "description" => "description", "licenses" => ["Apache"]}})
    |> HexWeb.Repo.update!
    package = HexWeb.Repo.get_by(Package, name: "ecto")
    assert length(package.meta.maintainers) == 2
  end

  test "validate blank description in metadata", %{user: user} do
    changeset = Package.build(user, pkg_meta(%{name: "ecto", description: ""}))
    assert changeset.errors == []
    assert [description: {"can't be blank", _}] = changeset.changes.meta.errors
  end

  test "validate invalid link in metadata", %{user: user} do
    meta = pkg_meta(%{name: "ecto", description: "DSL",
                      links: %{"docs" => "https://hexdocs.pm", "a" => "aaa", "b" => "bbb"}})
    changeset = Package.build(user, meta)

    assert changeset.errors == []
    assert [links: {"invalid link \"aaa\"", _},
            links: {"invalid link \"bbb\"", _}] =
      changeset.changes.meta.errors
  end

  test "packages are unique", %{user: user} do
    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!
    assert {:error, _} = Package.build(user, pkg_meta(%{name: "ecto", description: "Domain-specific language"})) |> HexWeb.Repo.insert
  end

  test "reserved names", %{user: user} do
    assert {:error, %{errors: [name: {"is reserved", _}]}} = Package.build(user, pkg_meta(%{name: "elixir", description: "Awesomeness."})) |> HexWeb.Repo.insert
  end

  test "sort packages by downloads", %{user: user} do
    phoenix =
      Package.build(user, pkg_meta(%{name: "phoenix", description: "Web framework"}))
      |> HexWeb.Repo.insert!
    rel =
      HexWeb.Release.build(phoenix, rel_meta(%{version: "0.0.1", app: "phoenix"}), "")
      |> HexWeb.Repo.insert!
    HexWeb.Repo.insert!(%HexWeb.Download{release: rel, day: HexWeb.Utils.utc_today, downloads: 10})

    :ok = HexWeb.Repo.refresh_view(HexWeb.PackageDownload)

    Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    |> HexWeb.Repo.insert!

    packages =
      Package.all(1, 10, nil, :downloads)
      |> HexWeb.Repo.all
      |> Enum.map(& &1.name)

    assert packages == ["phoenix", "ecto"]
  end

  describe "search" do
    test "extra metadata" do
      create_mock_package("nerves", "DSL", 1)
      create_mock_package("nerves_pkg", "DSL", 2)

      search = [
        {"name:nerves extra:list,[a]", 1},
        {"name:nerves* extra:foo,bar,baz", 2},
        {"name:nerves* extra:list,[1]", 1}]
      for {s, len} <- search do
        p = Package.all(1, 10, s, nil)
        |> HexWeb.Repo.all
        assert length(p) == len
      end
    end

    test "without metadata should be able to find keyword in description" do
      create_mock_package("ubertuffer", "A dummy js wrapper for xyz", 3)
      p = Package.all(1, 10, "xyz", nil) |> HexWeb.Repo.all
      assert length(p) == 1
    end

    test "without metdata should be able to find keyword in name" do
      create_mock_package("ubertuffer", "A dummy js wrapper for xyz", 3)
      p = Package.all(1, 10, "ubertuffer", nil) |> HexWeb.Repo.all
      assert length(p) == 1
    end

    test "partial query in name without metadata should be supported" do
      create_mock_package("jsx", "DSL", 1)
      create_mock_package("json", "DSL", 2)
      create_mock_package("ubertuffer", "A dummy js wrapper for xyz", 3)
      create_mock_package("uberspeedoflight", "A fast module", 4)

      search = [
        {"jso", 1},
        {"tuffer", 1},
        {"son", 1},
        {"ube", 2},
        {"ub", 2},
        {"js", 3}
      ]

      for {s, len} <- search do
        p = Package.all(1, 10, s, nil)
        |> HexWeb.Repo.all
        assert length(p) == len, "Failed found #{length(p)} instead of #{len} packages for query #{s}"
      end
    end
  end

  test "partial query in description without metdata should be supported" do
    create_mock_package("ubermock", "A modulo module for speedometer", 1)
    create_mock_package("ubertuffer", "Speeding is not a mock", 3)

    search = [
      {"spee", 2},
      {"mo", 2}
    ]

    for {s, len} <- search do
      p = Package.all(1, 10, s, nil)
      |> HexWeb.Repo.all
      assert length(p) == len, "Failed found #{length(p)} instead of #{len} packages for query #{s}"
    end
  end

  defp create_mock_package(package_name, package_description, item_index) do
    meta = %{
      "maintainers"  => ["justin"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "https://github.com", "docs" => "https://hexdocs.pm"},
      "description"  => "description",
      "extra"        => %{"foo" => %{"bar" => "baz"}, "list" => ["a", item_index]}
    }

    user = HexWeb.Repo.get_by!(User, username: "eric")

    Package.build(user, pkg_meta(%{name: package_name, description: package_description}))
    |> HexWeb.Repo.insert!
    |> Package.update(%{"meta" => meta})
    |> HexWeb.Repo.update!
  end
end
