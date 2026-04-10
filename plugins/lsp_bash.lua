-- mod-version:3
local core = require "core"

core.add_thread(function()
  local ok, lspconfig = pcall(require, "plugins.lsp.config")
  if not ok then
    core.log_quiet("lsp_bash: lite-xl-lsp not found — skipping bash LSP")
    return
  end
  local ok2, err = pcall(function() lspconfig.bashls.setup() end)
  if not ok2 then
    core.log_quiet("lsp_bash: failed to register bash-language-server: %s", err)
  else
    core.log_quiet("lsp_bash: bash-language-server registered")
  end
end)
