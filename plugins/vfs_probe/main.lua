commander.command("example.vfs_probe.stat_panel", function(ctx)
  if ctx.panel == nil or ctx.panel.uri == nil then
    commander.status("No active panel URI")
    return
  end

  local action, err = commander.vfs.request("stat", ctx.panel.uri)
  if err ~= nil then
    commander.status(err.code)
    return
  end

  commander.status(action.operation .. " requested for " .. action.uri)
end)
