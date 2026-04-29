

# app.R
# Entry point — sources global.R, ui.R, server.R

source("global.R")
source("ui.R")
source("server.R")

shinyApp(ui = ui, server = server)
