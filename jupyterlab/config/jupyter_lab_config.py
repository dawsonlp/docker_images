c = get_config()

c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.root_dir = "/notebooks"
c.ServerApp.token = ""
c.ServerApp.password = ""
c.ServerApp.allow_origin = "*"
c.ServerApp.terminals_enabled = True

c.MappingKernelManager.cull_idle_timeout = 3600
c.MappingKernelManager.cull_interval = 300
c.MappingKernelManager.cull_connected = False
