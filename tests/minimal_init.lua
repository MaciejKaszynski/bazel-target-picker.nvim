-- Minimal runtimepath setup so tests can run standalone, without the full
-- personal Neovim config:
--   nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(plugin_root)
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/site/pack/core/opt/plenary.nvim")
