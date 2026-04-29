# server.R

server <- function(input, output, session) {
  
  # ── Reactive state ────────────────────────────────────────────────────────────
  rv <- reactiveValues(
    huc_sf        = NULL,
    fema_sf       = NULL,
    levee_sf      = NULL,
    census_sf     = NULL,
    levee_areas   = NULL,
    custom_extent = NULL,
    census_data   = NULL,  # named list: $huc, $protected, $impacted
    fetch_msg     = NULL,
    last_bbox     = NULL,
    selected_huc  = NULL,  # sf: the single clicked HUC polygon
    selected_huc_id = NULL # character: layerId of selected polygon
  )
  
  # ── Base map: CONUS view ───────────────────────────────────────────────────────
  output$main_map <- renderLeaflet({
    leaflet() |>
      addProviderTiles(map_basemaps[["CartoDB light"]], layerId = "basemap") |>
      setView(lng = CONUS_CENTER["lng"], lat = CONUS_CENTER["lat"], zoom = CONUS_ZOOM) |>
      addScaleBar(position = "bottomleft") |>
      addMeasure(
        position          = "topleft",
        primaryLengthUnit = "kilometers",
        primaryAreaUnit   = "sqmeters"
      ) |>
      addLayersControl(
        overlayGroups = c(
          "HUC boundaries", "NLCD",
          "Levee lines", "Levee-protected", "Levee-impacted",
          "Custom extent"
        ),
        options = layersControlOptions(collapsed = FALSE)
      ) |>
      hideGroup(c("NLCD", "Custom extent"))
  })
  
  # ── Basemap swap ──────────────────────────────────────────────────────────────
  observeEvent(input$basemap, {
    leafletProxy("main_map") |>
      addProviderTiles(map_basemaps[[input$basemap]], layerId = "basemap")
  })
  
  # ── Current map viewport bbox (reactive) ──────────────────────────────────────
  # Leaflet reports bounds as input$main_map_bounds: list(north, east, south, west)
  map_bbox <- reactive({
    b <- input$main_map_bounds
    if (is.null(b)) return(unname(CONUS_BBOX))
    c(xmin = b$west, ymin = b$south, xmax = b$east, ymax = b$north)
  })
  
  map_zoom <- reactive({
    input$main_map_zoom %||% CONUS_ZOOM
  })
  
  # ── HUC-2: auto-load on startup (lightweight, ~18 polygons) ──────────────────
  # Load HUC-2 boundaries automatically when app starts — no button needed.
  observe({
    # Only fire once: when huc_sf is still NULL and map has initialized
    req(is.null(rv$huc_sf), !is.null(input$main_map_bounds))
    isolate({
      huc <- tryCatch(fetch_huc_boundaries(huc_level = 2), error = function(e) NULL)
      rv$huc_sf <- huc
    })
  })
  
  # ── Zoom hint: warn if zoom is too low for selected HUC level ─────────────────
  output$huc_zoom_hint <- renderUI({
    lvl      <- as.character(input$huc_level)
    min_zoom <- HUC_MIN_ZOOM[lvl]
    cur_zoom <- map_zoom()
    
    if (as.integer(input$huc_level) == 2) return(NULL)
    
    if (cur_zoom < min_zoom) {
      div(class = "warn-bar",
          icon("triangle-exclamation"), " ",
          glue("Zoom in more before loading HUC-{input$huc_level} (current: {cur_zoom}, need: {min_zoom}+)")
      )
    } else {
      div(class = "huc-hint",
          icon("circle-check"), glue(" Ready to load HUC-{input$huc_level}")
      )
    }
  })
  
  # ── Fetch button: load HUC boundaries for current view ────────────────────────
  observeEvent(input$fetch_data, {
    huc_level <- as.integer(input$huc_level)
    zoom      <- map_zoom()
    min_zoom  <- HUC_MIN_ZOOM[as.character(huc_level)]
    cat("\n=== FETCH CLICKED ===\n")
    cat("HUC level:", huc_level, "| Zoom:", zoom, "\n")
    
    if (huc_level > 2 && zoom < min_zoom) {
      showNotification(
        glue("Zoom {zoom} may be too low for HUC-{huc_level}. Consider zooming in."),
        type = "message", duration = 4
      )
    }
    
    bbox <- map_bbox()
    rv$last_bbox    <- bbox
    rv$selected_huc <- NULL  # clear selection when reloading
    
    rv$fetch_msg <- "Fetching HUC boundaries..."
    rv$huc_sf <- tryCatch(
      fetch_huc_boundaries(huc_level = huc_level, bbox = bbox),
      error = function(e) { cat("HUC ERROR:", e$message, "\n"); NULL }
    )
    cat("HUC rows fetched:", nrow(rv$huc_sf %||% data.frame()), "\n")
    rv$fema_sf <- NULL
    
    rv$fetch_msg <- glue(
      "{format(Sys.time(), '%H:%M:%S')} | ",
      "HUC-{huc_level}: {nrow(rv$huc_sf %||% data.frame())} loaded | Click a polygon to load detail data"
    )
  })
  
  # ── HUC polygon click: select HUC and load all detail data ────────────────────
  observeEvent(input$main_map_shape_click, {
    click <- input$main_map_shape_click
    req(!is.null(click), !is.null(rv$huc_sf))
    
    # Only respond to clicks on HUC boundaries group
    if (!isTRUE(click$group == "HUC boundaries")) return()
    
    huc <- rv$huc_sf
    idx <- which(paste0("huc_", seq_len(nrow(huc))) == click$id)
    if (length(idx) == 0) return()
    
    selected <- huc[idx, ]
    rv$selected_huc    <- selected
    rv$selected_huc_id <- click$id
    
    # Highlight selected polygon
    leafletProxy("main_map") |>
      clearGroup("HUC selected") |>
      addPolygons(
        data      = selected,
        group     = "HUC selected",
        fillColor = "#2166ac",
        fillOpacity = 0.15,
        color     = "#2166ac",
        weight    = 3,
        options   = pathOptions(pane = "markerPane")
      )
    
    # Get bbox of selected HUC
    sel_bbox <- as.numeric(st_bbox(selected))
    cat("\n=== HUC SELECTED ===\n")
    cat("BBox:", sel_bbox, "\n")
    
    rv$fetch_msg <- "Loading data for selected HUC..."
    
    # NLD levees for selected HUC bbox
    rv$levee_sf <- tryCatch(
      fetch_nld_levees(sel_bbox),
      error = function(e) { cat("NLD ERROR:", e$message, "\n"); NULL }
    )
    
    # Levee classification
    rv$levee_areas <- tryCatch(
      classify_levee_areas(rv$levee_sf, input$levee_buffer_m),
      error = function(e) { cat("CLASSIFY ERROR:", e$message, "\n"); NULL }
    )
    
    # Census summary for: full HUC, protected areas, impacted areas
    selected_vars <- input$census_vars_selected
    cat("Census vars selected in click handler:", length(selected_vars), "\n")
    if (length(selected_vars) > 0) cat("Vars:", paste(selected_vars, collapse=", "), "\n")
    if (length(selected_vars) > 0) {
      rv$fetch_msg <- "Fetching census data..."
      
      # Full HUC — clip to selected HUC polygon
      huc_census <- tryCatch(
        fetch_census_summary(selected_vars, sel_bbox,
                             clip_geom = st_geometry(selected)),
        error = function(e) NULL
      )
      
      # Protected areas — clip to leveed area polygons
      prot_census <- NULL
      if (!is.null(rv$levee_areas$protected) &&
          inherits(rv$levee_areas$protected, "sf") &&
          nrow(rv$levee_areas$protected) > 0) {
        prot_bbox <- as.numeric(st_bbox(rv$levee_areas$protected))
        prot_census <- tryCatch(
          fetch_census_summary(selected_vars, prot_bbox,
                               clip_geom = st_geometry(rv$levee_areas$protected)),
          error = function(e) NULL
        )
      }
      
      # Impacted areas — clip to impacted zone geometry
      imp_census <- NULL
      if (!is.null(rv$levee_areas$impacted)) {
        imp_geom <- if (inherits(rv$levee_areas$impacted, "sfc"))
          rv$levee_areas$impacted
        else
          st_geometry(rv$levee_areas$impacted)
        imp_bbox <- as.numeric(st_bbox(imp_geom))
        imp_census <- tryCatch(
          fetch_census_summary(selected_vars, imp_bbox,
                               clip_geom = imp_geom),
          error = function(e) NULL
        )
      }
      
      cat("HUC census result:", !is.null(huc_census), "\n")
      if (!is.null(huc_census)) cat("HUC census keys:", paste(names(huc_census), collapse=", "), "\n")
      
      rv$census_data <- list(
        huc       = huc_census,
        protected = prot_census,
        impacted  = imp_census
      )
      cat("Census stored. Keys in rv$census_data:", paste(names(rv$census_data), collapse=", "), "\n")
    }
    
    rv$fetch_msg <- glue(
      "{format(Sys.time(), '%H:%M:%S')} | ",
      "Levees: {nrow(rv$levee_sf$leveed_areas %||% data.frame())} | ",
      "Protected: {nrow(rv$levee_areas$protected %||% data.frame())} polygons"
    )
  })
  
  # ── Re-fetch HUC when level toggle changes ────────────────────────────────────
  # For HUC-2: always re-fetch (no bbox needed, fast).
  # For finer levels: prompt user to click the fetch button.
  observeEvent(input$huc_level, {
    if (as.integer(input$huc_level) == 2) {
      rv$huc_sf <- tryCatch(fetch_huc_boundaries(huc_level = 2), error = function(e) NULL)
    } else {
      # Clear old boundaries so the map doesn't show stale HUC-2 outlines
      # while waiting for the user to click fetch at the right zoom
      rv$huc_sf <- NULL
    }
  }, ignoreInit = TRUE)
  
  # ── Re-classify levees when buffer slider changes ──────────────────────────────
  observeEvent(input$levee_buffer_m, {
    req(rv$levee_sf)
    rv$levee_areas <- classify_levee_areas(rv$levee_sf, input$levee_buffer_m)
  })
  
  # ── Map update: HUC boundaries ────────────────────────────────────────────────
  observe({
    huc   <- rv$huc_sf
    proxy <- leafletProxy("main_map")
    proxy |> clearGroup("HUC boundaries")
    
    # Exit silently if no data — don't use req() so clearing always happens
    cat("HUC observer fired | rows:", nrow(huc %||% data.frame()), 
        "| show_huc_bounds:", isTRUE(input$show_huc_bounds), "\n")
    if (is.null(huc) || nrow(huc) == 0) return()
    if (!isTRUE(input$show_huc_bounds)) return()
    
    huc_level <- as.character(input$huc_level)
    weight    <- switch(huc_level, "2" = 2.5, "4" = 1.8, "8" = 1.2, "12" = 0.8, 1.2)
    
    # Find name column safely — check several common patterns
    col_names <- names(huc)
    name_col  <- col_names[col_names %in% c("name", "Name", "NAME",
                                            "huc2", "huc4", "huc8", "huc12")][1]
    if (is.na(name_col)) name_col <- col_names[1]
    
    # Build labels safely outside the formula
    labels <- tryCatch(as.character(huc[[name_col]]), error = function(e) NULL)
    
    proxy |>
      addPolygons(
        data             = huc,
        group            = "HUC boundaries",
        fillColor        = "transparent",
        fillOpacity      = 0,
        color            = "#2166ac",
        weight           = weight,
        opacity          = 0.85,
        label            = labels,
        highlightOptions = highlightOptions(
          weight      = weight + 1.5,
          color       = "#1a5276",
          fillColor   = "#2166ac",
          fillOpacity = 0.07,
          bringToFront = TRUE
        ),
        layerId = paste0("huc_", seq_len(nrow(huc)))
      )
  })
  
  # ── Map update: NLCD ──────────────────────────────────────────────────────────
  observe({
    proxy <- leafletProxy("main_map")
    proxy |> clearGroup("NLCD")
    req(isTRUE(input$show_nlcd))
    proxy |>
      addWMSTiles(
        baseUrl = ENDPOINTS$nlcd_wms,
        group   = "NLCD",
        layers  = "NLCD_2021_Land_Cover_L48",
        options = WMSTileOptions(format = "image/png", transparent = TRUE,
                                 version = "1.1.1", opacity = 0.7)
      )
  })
  
  # ── FEMA flood zones ──────────────────────────────────────────────────────────
  # TODO: Re-enable when a reliable tile/WMS source is confirmed.
  # The NFHL export endpoint (hazards.fema.gov) returns PNG but doesn't support
  # XYZ tiles and WMS 400s. Will revisit with custom flood model integration.
  
  # ── Map update: levee layers ──────────────────────────────────────────────────
  observe({
    levee <- rv$levee_sf
    areas <- rv$levee_areas
    proxy <- leafletProxy("main_map")
    proxy |>
      clearGroup("Levee lines") |>
      clearGroup("Levee-protected") |>
      clearGroup("Levee-impacted")
    
    # Embankment + floodwall lines
    line_layers <- Filter(Negate(is.null), list(
      levee$embankments,
      levee$floodwalls
    ))
    if (length(line_layers) > 0) {
      for (layer in line_layers) {
        if (!is.null(layer) && nrow(layer) > 0) {
          proxy |>
            addPolylines(
              data   = layer,
              group  = "Levee lines",
              color  = "#8B4513",
              weight = 1.5,
              opacity = 0.8,
              popup  = "Levee embankment / floodwall"
            )
        }
      }
    }
    
    # Protected areas
    if (isTRUE(input$show_levee_protected) &&
        !is.null(areas$protected) && inherits(areas$protected, "sf") &&
        nrow(areas$protected) > 0) {
      proxy |>
        addPolygons(
          data        = areas$protected,
          group       = "Levee-protected",
          fillColor   = "#fee090",
          fillOpacity = 0.5,
          color       = "#d4a600",
          weight      = 1,
          popup       = "Levee-protected area"
        )
    }
    
    # Impacted areas
    if (isTRUE(input$show_levee_impacted) &&
        !is.null(areas$impacted) && inherits(areas$impacted, c("sf", "sfc"))) {
      impacted_sf <- if (inherits(areas$impacted, "sfc")) st_sf(geometry = areas$impacted) else areas$impacted
      proxy |>
        addPolygons(
          data        = impacted_sf,
          group       = "Levee-impacted",
          fillColor   = "#fc8d59",
          fillOpacity = 0.35,
          color       = "#d73027",
          weight      = 0.8,
          popup       = paste0("Levee-impacted area (", input$levee_buffer_m, "m buffer)")
        )
    }
  })
  
  # ── Flood scenario ────────────────────────────────────────────────────────────
  # TODO: Re-enable when custom flood models are integrated.
  # Scenario definitions are preserved in FLOOD_SCENARIOS (global.R).
  # observe({
  #   proxy    <- leafletProxy("main_map")
  #   scenario <- input$flood_scenario
  #   fema     <- rv$fema_sf
  #   proxy |> clearGroup("Flood scenario")
  #   req(scenario != "none", !is.null(fema), nrow(fema) > 0)
  #   scen_def <- FLOOD_SCENARIOS[[names(FLOOD_SCENARIOS)[sapply(FLOOD_SCENARIOS, \(s) s$id == scenario)]]]
  #   req(!is.null(scen_def))
  #   scenario_sf <- fema |> filter(FLD_ZONE %in% scen_def$fema_zones)
  #   req(nrow(scenario_sf) > 0)
  #   proxy |>
  #     addPolygons(data=scenario_sf, group="Flood scenario",
  #       fillColor=scen_def$color, fillOpacity=0.55, color=scen_def$color, weight=1) |>
  #     showGroup("Flood scenario")
  # })
  
  # Census display moved to stat cards — no map overlay
  
  # ── Map update: custom flood extent ───────────────────────────────────────────
  observe({
    proxy  <- leafletProxy("main_map")
    custom <- rv$custom_extent
    proxy |> clearGroup("Custom extent")
    req(!is.null(custom))
    proxy |>
      addPolygons(
        data        = custom,
        group       = "Custom extent",
        fillColor   = "#5e3c99",
        fillOpacity = 0.4,
        color       = "#5e3c99",
        weight      = 1.5,
        popup       = "Custom flood extent"
      ) |>
      showGroup("Custom extent")
  })
  
  # ── Handle custom extent upload ────────────────────────────────────────────────
  observeEvent(input$custom_flood_extent, {
    req(input$custom_flood_extent)
    rv$custom_extent <- tryCatch(
      st_read(input$custom_flood_extent$datapath, quiet = TRUE) |> st_transform(4326),
      error = function(e) {
        showNotification(paste("Could not read file:", e$message), type = "error", duration = 8)
        NULL
      }
    )
  })
  
  # ── Click info panel ──────────────────────────────────────────────────────────
  output$click_info <- renderUI({
    sel <- rv$selected_huc
    if (is.null(sel)) {
      return(p("Click a HUC polygon to select it and load levee + census data.",
               style = "color:#888; font-size:0.85rem;"))
    }
    
    # Find name column
    name_col <- names(sel)[names(sel) %in% c("name","Name","NAME")][1]
    huc_col  <- names(sel)[grep("^huc", names(sel), ignore.case=TRUE)][1]
    huc_name <- if (!is.na(name_col)) sel[[name_col]][1] else "—"
    huc_code <- if (!is.na(huc_col))  sel[[huc_col]][1]  else "—"
    area_km2 <- round(as.numeric(st_area(sel)) / 1e6, 0)
    
    div(
      style = "display:flex; gap:16px; flex-wrap:wrap;",
      div(
        div(style="font-size:0.7rem;color:#888;text-transform:uppercase;", "Selected HUC"),
        div(style="font-size:1rem;font-weight:600;", huc_name)
      ),
      div(
        div(style="font-size:0.7rem;color:#888;text-transform:uppercase;", "HUC code"),
        div(style="font-size:1rem;", huc_code)
      ),
      div(
        div(style="font-size:0.7rem;color:#888;text-transform:uppercase;", "Area"),
        div(style="font-size:1rem;", formatC(area_km2, format="d", big.mark=","), " km²")
      )
    )
  })
  
  # ── Stat cards ────────────────────────────────────────────────────────────────
  output$stat_cards <- renderUI({
    n_huc    <- nrow(rv$huc_sf    %||% data.frame())
    n_levees <- nrow(rv$levee_sf$leveed_areas %||% data.frame())
    
    prot_area <- if (!is.null(rv$levee_areas$protected) &&
                     inherits(rv$levee_areas$protected, "sf") &&
                     nrow(rv$levee_areas$protected) > 0) {
      round(as.numeric(sum(st_area(rv$levee_areas$protected), na.rm = TRUE)) / 1e6, 1)
    } else 0
    
    # Base spatial stats
    base_cards <- list(
      stat_card("HUC polygons",   n_huc,     glue("HUC-{input$huc_level} in view")),
      stat_card("Levee systems",  n_levees,  "NLD leveed areas in view"),
      stat_card("Protected area", prot_area, "km² levee-protected")
    )
    
    # Census numeric stats (non-percentage variables) from HUC-level data
    census_cards <- list()
    cd <- rv$census_data$huc
    if (!is.null(cd)) {
      pct_vars <- grep("^%", names(cd), value = TRUE)
      num_vars <- setdiff(names(cd), pct_vars)
      
      for (var in num_vars) {
        val <- cd[[var]]
        if (!is.null(val) && !is.na(val)) {
          fmt <- if (grepl("income", var, ignore.case = TRUE)) {
            paste0("$", formatC(val, format = "f", digits = 0, big.mark = ","))
          } else if (grepl("year", var, ignore.case = TRUE)) {
            formatC(val, format = "f", digits = 0, big.mark = "")
          } else {
            formatC(val, format = "f", digits = 0, big.mark = ",")
          }
          census_cards[[var]] <- stat_card(var, fmt, "selected HUC median/total")
        }
      }
    }
    
    c(base_cards, census_cards)
  })
  
  # ── Census demographic bar chart ───────────────────────────────────────────────
  output$census_chart <- renderUI({
    cd <- rv$census_data
    if (is.null(cd)) return(
      p("Click a HUC polygon to load census demographics.",
        style = "color:#888; font-size:0.83rem;")
    )
    
    huc_data  <- cd$huc
    prot_data <- cd$protected
    imp_data  <- cd$impacted
    
    if (is.null(huc_data)) return(
      p("No census data available for selected HUC.",
        style = "color:#888; font-size:0.83rem;")
    )
    
    pct_vars <- grep("^%", names(huc_data), value = TRUE)
    if (length(pct_vars) == 0) return(NULL)
    
    VAR_COLORS <- c(
      "% White alone"         = "#4e79a7",
      "% Black or Afr. Am."  = "#f28e2b",
      "% Hispanic/Latino"     = "#59a14f",
      "% Owner-occupied"      = "#76b7b2",
      "% Below poverty level" = "#e15759"
    )
    
    # Column header
    header <- div(
      style = "display:grid; grid-template-columns:1fr 60px 60px 60px; gap:4px;
               font-size:0.68rem; color:#888; font-weight:600; margin-bottom:6px;
               text-transform:uppercase; letter-spacing:0.04em;",
      div(),
      div(style="text-align:center;", "HUC"),
      div(style="text-align:center; color:#d4a600;", "Prot."),
      div(style="text-align:center; color:#d73027;", "Imp.")
    )
    
    bars <- lapply(pct_vars, function(var) {
      huc_val  <- huc_data[[var]]
      prot_val <- if (!is.null(prot_data)) prot_data[[var]] else NA
      imp_val  <- if (!is.null(imp_data))  imp_data[[var]]  else NA
      
      if (is.null(huc_val) || is.na(huc_val)) return(NULL)
      color <- VAR_COLORS[var] %||% "#888888"
      
      make_bar <- function(val, bar_color) {
        if (is.null(val) || is.na(val)) {
          return(div(style="font-size:0.72rem; color:#ccc; text-align:center;", "—"))
        }
        pct <- min(max(round(val, 1), 0), 100)
        div(
          div(style=glue("font-size:0.72rem; text-align:center; font-weight:600; color:{bar_color};"),
              glue("{pct}%")),
          div(style="background:#f0f0f0; border-radius:3px; height:7px; margin-top:2px;",
              div(style=glue("width:{pct}%; height:100%; background:{bar_color}; border-radius:3px;"))
          )
        )
      }
      
      div(
        style = "display:grid; grid-template-columns:1fr 60px 60px 60px;
                 gap:4px; align-items:center; margin-bottom:8px;",
        div(style="font-size:0.75rem;", gsub("^% ", "", var)),
        make_bar(huc_val,  color),
        make_bar(prot_val, "#d4a600"),
        make_bar(imp_val,  "#d73027")
      )
    })
    
    tagList(header, bars)
  })
  
  # ── Legend ────────────────────────────────────────────────────────────────────
  output$map_legend <- renderUI({
    row <- function(color, label) {
      div(style = "display:flex;align-items:center;margin-bottom:4px;font-size:0.82rem;",
          span(class = "legend-swatch", style = glue("background:{color};")),
          span(label)
      )
    }
    tagList(
      # FEMA legend removed — layer temporarily disabled
      if (input$show_levee_protected || input$show_levee_impacted) {
        div(
          p(strong("Levee areas"), style = "font-size:0.78rem;margin:8px 0 4px;"),
          if (input$show_levee_protected) row("#fee090", "Levee-protected"),
          if (input$show_levee_impacted)  row("#fc8d59", "Levee-impacted zone")
        )
      },
      # Flood scenario legend removed — feature temporarily disabled
    )
  })
  
  # ── Active layer badges ────────────────────────────────────────────────────────
  output$active_layers_badge <- renderUI({
    badges <- c()
    if (!is.null(rv$huc_sf))   badges <- c(badges, glue("HUC-{input$huc_level}"))
    # FEMA badge removed — layer temporarily disabled
    if (!is.null(rv$levee_sf)) badges <- c(badges, "NLD")
    if (!is.null(rv$census_data)) badges <- c(badges, "Census")
    # Flood scenario badge removed — feature temporarily disabled
    lapply(badges, \(b) span(b, class = "layer-badge badge bg-primary"))
  })
  
  # ── Fetch status ──────────────────────────────────────────────────────────────
  output$fetch_status <- renderUI({
    msg <- rv$fetch_msg
    if (is.null(msg)) return(NULL)
    div(class = "status-bar mt-2", icon("clock"), " ", msg)
  })
  
  # ── Custom extent status ───────────────────────────────────────────────────────
  output$custom_extent_status <- renderUI({
    if (is.null(rv$custom_extent)) return(NULL)
    div(class = "status-bar",
        icon("check-circle"), glue(" {nrow(rv$custom_extent)} feature(s) loaded")
    )
  })
}