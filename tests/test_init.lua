local expect, eq = MiniTest.expect, MiniTest.expect.equality

local c = MiniTest.new_child_neovim()

describe("completion", function()
  before_each(function()
    c.restart({ "-u", "scripts/minimal_init.lua" })
    c.o.lines = 10
    c.o.columns = 40
    c.api.nvim_buf_set_text(0, 0, 0, 0, 0, { "require('iofwjipo')" })
    c.lua([[require("llemper").setup()]])
  end)

  it("should initialize without errors", function()
    c.type_keys("i")
    expect.reference_screenshot(c.get_screenshot())
  end)
end)
