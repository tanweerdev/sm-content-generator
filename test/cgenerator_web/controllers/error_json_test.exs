defmodule SMGWeb.ErrorJSONTest do
  use SMGWeb.ConnCase, async: true

  test "renders 404" do
    assert SMGWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert SMGWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
