local config = {}

config.font_size = 16
config.font_file = "MesloLGSNerdFontMono-Regular.ttf"
config.indent_size = 4
config.tab_type = "soft"
config.line_height = 1.2
config.scroll_past_end = true

config.theme = "token"
config.transparency = false
config.transparency_alpha = 0.95

config.modal_enabled = true
config.default_mode = "normal"

config.formatters = {
  lua        = { cmd = "stylua",    args = { "-" } },
  python     = { cmd = "black",     args = { "-q", "-" } },
  javascript = { cmd = "prettier",  args = { "--stdin-filepath", "{file}" } },
  typescript = { cmd = "prettier",  args = { "--stdin-filepath", "{file}" } },
  html       = { cmd = "prettier",  args = { "--stdin-filepath", "{file}" } },
  css        = { cmd = "prettier",  args = { "--stdin-filepath", "{file}" } },
  json       = { cmd = "prettier",  args = { "--stdin-filepath", "{file}" } },
  yaml       = { cmd = "prettier",  args = { "--stdin-filepath", "{file}" } },
  markdown   = { cmd = "prettier",  args = { "--stdin-filepath", "{file}" } },
  shell      = { cmd = "shfmt",     args = { "-" } },
  rust       = { cmd = "rustfmt",   args = {} },
  go         = { cmd = "gofmt" },
}

config.linters = {
  python     = { cmd = "ruff",       args = { "check", "--stdin-filename", "{file}", "-" } },
  javascript = { cmd = "eslint_d",   args = { "--stdin", "--stdin-filename", "{file}", "--format", "compact" } },
  typescript = { cmd = "eslint_d",   args = { "--stdin", "--stdin-filename", "{file}", "--format", "compact" } },
  lua        = { cmd = "luacheck",   args = { "--formatter", "plain", "-" } },
  shell      = { cmd = "shellcheck", args = { "-f", "gcc", "-" } },
}

config.runners = {
  python     = { cmd = "python3",  args = { "{file}" } },
  javascript = { cmd = "node",     args = { "{file}" } },
  typescript = { cmd = "npx",      args = { "ts-node", "{file}" } },
  lua        = { cmd = "lua",      args = { "{file}" } },
  shell      = { cmd = "bash",     args = { "{file}" } },
  rust       = { cmd = "cargo",    args = { "run" } },
  go         = { cmd = "go",       args = { "run", "{file}" } },
  c          = { cmd = "sh",       args = { "-c", "cc -o /tmp/a.out {file} && /tmp/a.out" } },
  cpp        = { cmd = "sh",       args = { "-c", "c++ -o /tmp/a.out {file} && /tmp/a.out" } },
}

config.lsp_servers = {
  lua        = { cmd = "lua-language-server" },
  python     = { cmd = "pyright-langserver",          args = { "--stdio" } },
  javascript = { cmd = "typescript-language-server",   args = { "--stdio" } },
  typescript = { cmd = "typescript-language-server",   args = { "--stdio" } },
  html       = { cmd = "vscode-html-language-server",  args = { "--stdio" } },
  css        = { cmd = "vscode-css-language-server",   args = { "--stdio" } },
  json       = { cmd = "vscode-json-language-server",  args = { "--stdio" } },
  bash       = { cmd = "bash-language-server",         args = { "start" } },
}

return config
