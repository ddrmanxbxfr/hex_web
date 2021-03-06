defmodule Hexpm.Web.PageControllerTest do
  use Hexpm.ConnCase, async: true

  alias Hexpm.Repository.Package
  alias Hexpm.Repository.Release

  defp release_create(package, version, app, requirements, checksum, inserted_at) do
    release = Release.build(package, rel_meta(%{version: version, app: app, requirements: requirements}), checksum)
              |> Hexpm.Repo.insert!
    Ecto.Changeset.change(release, inserted_at: inserted_at)
    |> Hexpm.Repo.update!
  end

  setup do
    first_date  = ~N[2014-05-01 10:11:12]
    second_date = ~N[2014-05-02 10:11:12]
    last_date   = ~N[2014-05-03 10:11:12]

    eric = create_user("eric", "eric@example.com", "ericeric")

    foo = Package.build(eric, %{name: "foo", inserted_at: first_date, updated_at: first_date, meta: %{description: "foo", licenses: ["Apache"]}}) |> Hexpm.Repo.insert!
    bar = Package.build(eric, %{name: "bar", inserted_at: second_date, updated_at: second_date, meta: %{description: "bar", licenses: ["Apache"]}}) |> Hexpm.Repo.insert!
    other = Package.build(eric, %{name: "other", inserted_at: last_date, updated_at: last_date, meta: %{description: "other", licenses: ["Apache"]}}) |> Hexpm.Repo.insert!

    release_create(foo, "0.0.1", "foo", [], "", ~N[2014-05-03 10:11:01])
    release_create(foo, "0.0.2", "foo", [], "", ~N[2014-05-03 10:11:02])
    release_create(foo, "0.1.0", "foo", [], "", ~N[2014-05-03 10:11:03])
    release_create(bar, "0.0.1", "bar", [], "", ~N[2014-05-03 10:11:04])
    release_create(bar, "0.0.2", "bar", [], "", ~N[2014-05-03 10:11:05])
    release_create(other, "0.0.1", "other", [], "", ~N[2014-05-03 10:11:06])
    :ok
  end

  test "index" do
    logfile1 = read_fixture("s3_logs_1.txt")
    logfile2 = read_fixture("s3_logs_2.txt")

    Hexpm.Store.put("region", "bucket", "hex/2013-12-01-21-32-16-E568B2907131C0C0", logfile1, [])
    Hexpm.Store.put("region", "bucket", "hex/2013-12-01-21-32-19-E568B2907131C0C0", logfile2, [])
    Mix.Tasks.Hexpm.Stats.run(~D[2013-12-01], [["bucket", "region"]])

    conn = get build_conn(), "/"

    assert conn.status == 200
    assert conn.assigns.total["all"] == 9
    assert conn.assigns.total["week"] == 0
    assert [{"foo", %NaiveDateTime{}, %Hexpm.Repository.PackageMetadata{}, 7}, {"bar", %NaiveDateTime{}, %Hexpm.Repository.PackageMetadata{}, 2}] = conn.assigns.package_top
    assert conn.assigns.num_packages == 3
    assert conn.assigns.num_releases == 6
    assert Enum.count(conn.assigns.releases_new) == 6
    assert Enum.count(conn.assigns.package_new) == 3
  end
end
