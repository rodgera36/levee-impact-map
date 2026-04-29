# ui.R

ui <- page_sidebar(
  title = "Flood Risk Explorer — CONUS",
  theme = bs_theme(
    version    = 5,
    bootswatch = "flatly",
    primary    = "#2166ac",
    secondary  = "#5aae61"
  ),
  
  tags$head(
    tags$style(HTML("
      .map-container  { height: calc(100vh - 200px); min-height: 500px; }
      #main_map       { height: 100% !important; }
      .layer-badge    { font-size: 0.72rem; padding: 2px 6px; border-radius: 10px; margin-left: 4px; }
      .status-bar     { font-size: 0.8rem; color: #666; padding: 4px 8px;
                        background: #f5f5f5; border-radius: 4px; margin-bottom: 6px; }
      .warn-bar       { font-size: 0.8rem; color: #7a5000; padding: 4px 8px;
                        background: #fff3cd; border-radius: 4px; margin-bottom: 6px; }
      .stat-card      { background: #fff; border: 1px solid #dee2e6; border-radius: 8px;
                        padding: 10px 14px; margin-bottom: 8px; }
      .stat-label     { font-size: 0.75rem; color: #6c757d; text-transform: uppercase;
                        letter-spacing: 0.04em; }
      .stat-value     { font-size: 1.4rem; font-weight: 600; color: #2166ac; }
      .legend-swatch  { display:inline-block; width:14px; height:14px;
                        border-radius:3px; margin-right:5px; vertical-align:middle; }
      .section-header { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.08em;
                        color: #888; margin-top: 12px; margin-bottom: 4px; font-weight: 600; }
      .huc-hint       { font-size: 0.73rem; color: #999; font-style: italic; margin-top: 2px; }
    "))
  ),
  
  # ── Sidebar ──────────────────────────────────────────────────────────────────
  sidebar = sidebar(
    width = 290,
    open  = TRUE,
    
    # Load button at top for easy access
    actionButton(
      "fetch_data",
      "Load layers for current view",
      class = "btn-primary w-100 mb-2",
      icon  = icon("layer-group")
    ),
    uiOutput("fetch_status"),
    
    hr(style = "margin: 8px 0"),
    
    # HUC level
    div(class = "section-header", "Watershed level"),
    radioButtons(
      "huc_level",
      label   = NULL,
      choices = c("HUC-2" = 2, "HUC-4" = 4, "HUC-8" = 8, "HUC-12" = 12),
      selected = 2,
      inline   = TRUE
    ),
    # Dynamic zoom hint
    uiOutput("huc_zoom_hint"),
    
    hr(style = "margin: 8px 0"),
    
    # Flood scenario — disabled until custom flood models are integrated
    # TODO: Re-enable selectInput("flood_scenario", ...) when models are ready
    
    hr(style = "margin: 8px 0"),
    
    # Levee display
    div(class = "section-header", "Levee layers"),
    checkboxInput("show_levee_protected", "Levee-protected areas", value = TRUE),
    checkboxInput("show_levee_impacted",  "Levee-impacted areas",  value = TRUE),
    sliderInput(
      "levee_buffer_m",
      "Impact buffer (m)",
      min = 100, max = 2000, value = 500, step = 100
    ),
    
    hr(style = "margin: 8px 0"),
    
    # Data layers
    div(class = "section-header", "Data layers"),
    checkboxInput("show_nlcd",       "NLCD land cover (WMS)",    value = FALSE),
    checkboxInput("show_huc_bounds", "HUC boundaries",           value = TRUE),
    # FEMA flood zones — temporarily disabled (see server.R TODO)
    
    hr(style = "margin: 8px 0"),
    
    # Census
    div(class = "section-header", "Census data"),
    div(class = "huc-hint", "Shows in summary stats panel after loading"),
    checkboxGroupInput(
      "census_vars_selected",
      label   = NULL,
      choices = names(CENSUS_VARS),
      selected = c("Total population", "Median household income",
                   "% White alone", "% Black or Afr. Am.",
                   "% Hispanic/Latino", "% Below poverty level",
                   "% Owner-occupied", "Median year built")
    ),
    
    hr(style = "margin: 8px 0"),
    
    # Basemap
    div(class = "section-header", "Basemap"),
    selectInput(
      "basemap",
      label   = NULL,
      choices = names(map_basemaps),
      selected = "CartoDB light"
    ),
    
    hr(style = "margin: 8px 0"),
    
    # Custom extent upload
    div(class = "section-header", "Custom flood extent"),
    fileInput(
      "custom_flood_extent",
      label       = NULL,
      accept      = c(".geojson", ".gpkg", ".shp"),
      placeholder = "Upload .geojson / .gpkg"
    ),
    uiOutput("custom_extent_status"),
    
  ),
  
  # ── Main panel ────────────────────────────────────────────────────────────────
  layout_columns(
    col_widths = c(9, 3),
    
    card(
      full_screen = TRUE,
      card_header(
        "Map view",
        uiOutput("active_layers_badge", inline = TRUE)
      ),
      div(class = "map-container",
          leafletOutput("main_map", height = "100%")
      )
    ),
    
    card(
      card_header("Summary stats"),
      uiOutput("stat_cards"),
      hr(),
      card_header("Demographics"),
      uiOutput("census_chart"),
      hr(),
      card_header("Legend"),
      uiOutput("map_legend")
    )
  ),
  
  card(
    max_height = "110px",
    card_header("Feature details (click map feature)"),
    uiOutput("click_info")
  )
)