function love.conf(t)
    t.identity = "terraui-love2d-demo"
    t.window.title = "TerraUI + Love2D"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.vsync = 1
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
end
