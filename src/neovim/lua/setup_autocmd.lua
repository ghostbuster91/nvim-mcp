-- The channel of the MCP server that ran this chunk. It is passed in because Neovim tells only the RPC caller its own
-- id, through nvim_get_api_info, and that call is not exposed to Lua (nvim_get_chan_info(0) answers nothing here).
local chan = ...

-- Every server that connects runs this chunk again, and the augroup below clears, so the newest autocmds have to
-- serve every server that is still attached: the set of channels lives outside the chunk.
_G.NVIM_MCP_CHANNELS = _G.NVIM_MCP_CHANNELS or {}
_G.NVIM_MCP_CHANNELS[chan] = true

-- Notifying channel 0 broadcasts to *every* attached channel, and a channel with no handler for these methods answers
-- with an error. Neovim 0.12 runs its own TUI as a separate process over RPC, so a broadcast makes Neovim log
-- `async error on channel 1: Invalid method: NVIM_MCP_LspAttach` for every LSP attach, and the user sees it.
local function notify(method, payload)
    for c in pairs(_G.NVIM_MCP_CHANNELS) do
        -- A server that went away leaves its autocmds behind, so drop the channel when it no longer takes messages.
        if not pcall(vim.rpcnotify, c, method, payload) then
            _G.NVIM_MCP_CHANNELS[c] = nil
        end
    end
end

local group = vim.api.nvim_create_augroup("NVIM_MCP_DiagnosticsChanged", { clear = true })

vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(args)
        notify("NVIM_MCP_DiagnosticsChanged", {
            buf = args.buf,
            diagnostics = args.data.diagnostics,
        })
    end,
})

vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
        local client_id = args.data.client_id
        local client = vim.lsp.get_client_by_id(client_id)

        if client then
            notify("NVIM_MCP_LspAttach", {
                client_name = client.name,
                client_id = client_id,
                buffer_id = args.buf,
                server_capabilities = client.server_capabilities,
                initialized = client.initialized,
                attach_time = vim.uv.now(),
            })
        end
    end,
})

vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(args)
        local client_id = args.data.client_id
        local client = vim.lsp.get_client_by_id(client_id)

        if client then
            notify("NVIM_MCP_LspDetach", {
                client_name = client.name,
                client_id = client_id,
                buffer_id = args.buf,
                detach_time = vim.uv.now(),
            })
        end
    end,
})

notify("NVIM_MCP", "setup diagnostics changed autocmd")
