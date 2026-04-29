# global.R
# Loaded once at startup by Shiny. Put packages, constants, and pure functions here.

# ── Packages ──────────────────────────────────────────────────────────────────
library(shiny)
library(bslib)
library(leaflet)
library(leaflet.extras)
library(sf)
library(terra)
library(dplyr)
library(tidycensus)
library(tigris)
library(httr2)
library(jsonlite)
library(glue)
library(nhdplusTools)
library(base64enc)

# ── Census API key ─────────────────────────────────────────────────────────────
# Set once: census_api_key("YOUR_KEY", install = TRUE)
# Get a free key at: https://api.census.gov/data/key_signup.html

# ── CONUS extent ───────────────────────────────────────────────────────────────
CONUS_BBOX   <- c(xmin = -124.85, ymin = 24.40, xmax = -66.88, ymax = 49.38)
CONUS_CENTER <- c(lng = -96, lat = 38)
CONUS_ZOOM   <- 4

# Minimum map zoom before fetching each HUC level.
# Prevents requesting thousands of fine-grained polygons at national extent.
HUC_MIN_ZOOM <- c("2" = 3, "4" = 5, "8" = 7, "12" = 9)

# ── HUC type strings for nhdplusTools::get_huc() ──────────────────────────────
HUC_TYPE <- c("2" = "huc02", "4" = "huc04", "8" = "huc08", "12" = "huc12")

# ── Flood scenario definitions ─────────────────────────────────────────────────
FLOOD_SCENARIOS <- list(
  "25-year flood"  = list(id = "25yr",    fema_zones = c("X"),                                 color = "#74c476"),
  "100-year flood" = list(id = "100yr",   fema_zones = c("A", "AE", "AH", "AO", "AR"),        color = "#2166ac"),
  "500-year flood" = list(id = "500yr",   fema_zones = c("X500", "B"),                         color = "#fdae61"),
  "Levee failure"  = list(id = "failure", fema_zones = c("A", "AE", "AH", "AO", "AR", "A99"), color = "#d73027")
)

# ── FEMA flood zone metadata ───────────────────────────────────────────────────
FEMA_ZONES <- list(
  high  = c("A", "AE", "AH", "AO", "AR", "A99", "V", "VE"),
  mod   = c("X500", "B"),
  low   = c("X", "C"),
  levee = c("A99")
)

FEMA_ZONE_COLORS <- c(
  "AE"   = "#2166ac",
  "AH"   = "#4393c3",
  "AO"   = "#74add1",
  "A"    = "#abd9e9",
  "A99"  = "#fee090",
  "X500" = "#fdae61",
  "X"    = "#d4e6f1",
  "V"    = "#1b7837",
  "VE"   = "#5aae61"
)

# ── NLCD class definitions ─────────────────────────────────────────────────────
NLCD_CLASSES <- list(
  "11" = list(label = "Open water",            color = "#476BA0"),
  "12" = list(label = "Perennial ice/snow",    color = "#D1DDF9"),
  "21" = list(label = "Developed, open space", color = "#DDC9C9"),
  "22" = list(label = "Developed, low",        color = "#D89382"),
  "23" = list(label = "Developed, medium",     color = "#BC4B4B"),
  "24" = list(label = "Developed, high",       color = "#8A2020"),
  "31" = list(label = "Barren land",           color = "#B2ADA3"),
  "41" = list(label = "Deciduous forest",      color = "#68AA63"),
  "42" = list(label = "Evergreen forest",      color = "#1C6330"),
  "43" = list(label = "Mixed forest",          color = "#B5C98E"),
  "52" = list(label = "Shrub/scrub",           color = "#CCBA7C"),
  "71" = list(label = "Grassland",             color = "#E2E2C1"),
  "81" = list(label = "Pasture/hay",           color = "#DBD83D"),
  "82" = list(label = "Cultivated crops",      color = "#AA7028"),
  "90" = list(label = "Woody wetlands",        color = "#BAD8EA"),
  "95" = list(label = "Emergent herbaceous",   color = "#70A3BA")
)

# ── Census variables (ACS5) ────────────────────────────────────────────────────
CENSUS_VARS <- list(
  "Total population"        = "B01003_001",
  "Median household income" = "B19013_001",
  "% White alone"           = list(num = "B02001_002", denom = "B02001_001"),
  "% Black or Afr. Am."    = list(num = "B02001_003", denom = "B02001_001"),
  "% Hispanic/Latino"       = list(num = "B03003_003", denom = "B03003_001"),
  "Median year built"       = "B25037_001",
  "% Owner-occupied"        = list(num = "B25003_002", denom = "B25003_001"),
  "% Below poverty level"   = list(num = "B17001_002", denom = "B17001_001")
)

# All CONUS state abbreviations
CONUS_STATES <- c(
  "AL","AZ","AR","CA","CO","CT","DE","FL","GA","ID","IL","IN","IA","KS","KY",
  "LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY",
  "NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA",
  "WV","WI","WY","DC"
)

# ── WMS / REST endpoints ───────────────────────────────────────────────────────
NFHL_BASE <- "https://hazards.fema.gov/arcgis/rest/services/public/NFHL/MapServer"
NLD_BASE  <- "https://geospatial.sec.usace.army.mil/dls/rest/services/NLD/Public/MapServer"

ENDPOINTS <- list(
  nlcd_wms        = "https://www.mrlc.gov/geoserver/mrlc_display/NLCD_2021_Land_Cover_L48/wms",
  nfhl_zones      = paste0(NFHL_BASE, "/28/query"),  # Flood Hazard Zones
  nfhl_wms        = paste0(NFHL_BASE, "/WMSServer"),
  # NLD layers (confirmed working)
  nld_leveed_areas = paste0(NLD_BASE, "/16/query"),  # Leveed Areas (polygons)
  nld_embankments  = paste0(NLD_BASE, "/11/query"),  # Embankments (lines)
  nld_floodwalls   = paste0(NLD_BASE, "/12/query"),  # Floodwalls (lines)
  nld_routes       = paste0(NLD_BASE, "/15/query")   # System Routes (lines)
)

# ── NULL coalescing ────────────────────────────────────────────────────────────
`%||%` <- function(a, b) if (is.null(a)) b else a

# ── Helper: clamp bbox to CONUS ───────────────────────────────────────────────
clamp_bbox_to_conus <- function(bbox) {
  # Accepts named or unnamed numeric vector of length 4: xmin,ymin,xmax,ymax
  bbox <- as.numeric(bbox)
  if (length(bbox) != 4 || any(is.na(bbox))) return(rep(NA_real_, 4))
  c(
    xmin = max(bbox[1], CONUS_BBOX["xmin"]),
    ymin = max(bbox[2], CONUS_BBOX["ymin"]),
    xmax = min(bbox[3], CONUS_BBOX["xmax"]),
    ymax = min(bbox[4], CONUS_BBOX["ymax"])
  )
}

# ── Helper: fetch HUC boundaries ──────────────────────────────────────────────
# HUC-2: loads from local cache (CONUS-wide fetch times out on all known APIs)
# HUC-4/8/12: uses nhdplusTools::get_huc() with the current map viewport bbox
fetch_huc_boundaries <- function(huc_level = 2, bbox = NULL) {
  
  if (huc_level == 2) {
    cache_path <- "data/huc2_conus.rds"
    if (file.exists(cache_path)) return(readRDS(cache_path))
    warning("HUC-2 cache not found — generate with setup.R")
    return(NULL)
  }
  
  if (is.null(bbox)) {
    warning("bbox required for HUC levels finer than HUC-2")
    return(NULL)
  }
  
  b <- clamp_bbox_to_conus(bbox)
  if (any(is.na(b))) { warning("Invalid bbox for HUC fetch"); return(NULL) }
  
  # Build a simple sf bbox object — unname to avoid coordinate name issues
  AOI <- tryCatch({
    bb <- structure(
      c(xmin = unname(b[1]), ymin = unname(b[2]),
        xmax = unname(b[3]), ymax = unname(b[4])),
      class = "bbox", crs = sf::st_crs(4326)
    )
    sf::st_as_sfc(bb)
  }, error = function(e) NULL)
  
  if (is.null(AOI)) return(NULL)
  
  huc_type <- HUC_TYPE[as.character(huc_level)]
  cat("Calling get_huc type:", huc_type, "\n")
  
  result <- tryCatch(
    get_huc(AOI = AOI, type = huc_type) |> st_transform(4326),
    error = function(e) {
      cat("get_huc ERROR:", e$message, "\n")
      NULL
    }
  )
  cat("get_huc rows:", nrow(result %||% data.frame()), "\n")
  result
}

# ── FEMA flood zones: served as WMS tiles ─────────────────────────────────────
# Layer 28 rejects all spatial queries regardless of parameters.
# We display it as a WMS tile overlay in Leaflet instead — no polygon fetch needed.
# The WMS URL is added directly in server.R via addWMSTiles().
#
# NFHL WMS endpoint (ESRI MapServer export):
FEMA_TILE_URL <- paste0(
  "https://hazards.fema.gov/arcgis/rest/services/public/NFHL/MapServer/",
  "export?bbox={xmin},{ymin},{xmax},{ymax}",
  "&bboxSR=4326&layers=show:28&size={width},{height}",
  "&imageSR=4326&format=png32&transparent=true&f=image"
)

# WMS server URL — use MapServer export which confirmed returns PNG
FEMA_WMS_URL <- "https://hazards.fema.gov/arcgis/rest/services/public/NFHL/MapServer"

# Stub kept for API compatibility — returns NULL, display handled via WMS tiles
fetch_fema_flood_zones <- function(bbox) NULL

# ── Helper: fetch a single NLD layer for a bbox ───────────────────────────────
fetch_nld_layer <- function(endpoint, bbox, max_records = 500) {
  b        <- clamp_bbox_to_conus(bbox)
  bbox_str <- paste(c(b["xmin"], b["ymin"], b["xmax"], b["ymax"]), collapse = ",")
  
  resp <- tryCatch(
    request(endpoint) |>
      req_url_query(
        where             = "1=1",
        geometry          = bbox_str,
        geometryType      = "esriGeometryEnvelope",
        inSR              = "4326",
        outSR             = "4326",
        spatialRel        = "esriSpatialRelIntersects",
        outFields         = "*",
        returnGeometry    = "true",
        f                 = "geojson",
        resultRecordCount = max_records
      ) |>
      req_error(is_error = \(r) FALSE) |>
      req_timeout(15) |>
      req_perform(),
    error = function(e) NULL
  )
  
  if (is.null(resp) || resp_status(resp) != 200) return(NULL)
  body <- resp_body_string(resp)
  if (grepl('"error"', body, fixed = TRUE)) return(NULL)
  
  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp))
  writeBin(charToRaw(body), tmp)
  tryCatch(st_read(tmp, quiet = TRUE), error = function(e) NULL)
}

# ── Helper: fetch all NLD levee layers for a bbox ─────────────────────────────
# Returns a list with:
#   $leveed_areas  — polygons representing areas protected by levees
#   $embankments   — levee embankment centerlines
#   $floodwalls    — floodwall centerlines
#   $routes        — system route lines
fetch_nld_levees <- function(bbox) {
  list(
    leveed_areas = fetch_nld_layer(ENDPOINTS$nld_leveed_areas, bbox),
    embankments  = fetch_nld_layer(ENDPOINTS$nld_embankments,  bbox),
    floodwalls   = fetch_nld_layer(ENDPOINTS$nld_floodwalls,   bbox),
    routes       = fetch_nld_layer(ENDPOINTS$nld_routes,       bbox)
  )
}


# ── Helper: fetch Census summary stats for all selected variables ──────────────
# Returns a named list of single summary values (median or weighted mean).
# clip_geom: optional sf/sfc to spatially clip tracts (more precise than bbox).
fetch_census_summary <- function(variable_keys, bbox, clip_geom = NULL) {
  b <- clamp_bbox_to_conus(bbox)
  if (any(is.na(b)) || b["xmin"] >= b["xmax"] || b["ymin"] >= b["ymax"]) return(NULL)
  
  bbox_sf <- tryCatch(
    st_as_sfc(st_bbox(setNames(as.numeric(b), c("xmin","ymin","xmax","ymax")), crs=4326)),
    error = function(e) { cat("bbox_sf ERROR:", e$message, "\n"); NULL }
  )
  if (is.null(bbox_sf)) return(NULL)
  
  # States in view
  states_in_view <- tryCatch({
    sb <- tigris::states(cb=TRUE, resolution="20m", year=2022, progress_bar=FALSE) |>
      st_transform(4326) |>
      filter(STUSPS %in% CONUS_STATES)
    sb$STUSPS[lengths(st_intersects(sb, bbox_sf)) > 0]
  }, error = function(e) CONUS_STATES)
  
  if (length(states_in_view) == 0) states_in_view <- CONUS_STATES
  
  # Collect all raw variable codes needed
  all_raw_vars <- unique(unlist(lapply(variable_keys, function(k) {
    vs <- CENSUS_VARS[[k]]
    if (is.character(vs)) vs else c(vs$num, vs$denom)
  })))
  
  cat("Census: fetching", length(all_raw_vars), "vars for", length(states_in_view), "states\n")
  
  tryCatch({
    dat <- get_acs(
      geography    = "tract",
      variables    = all_raw_vars,
      state        = states_in_view,
      geometry     = TRUE,
      year         = 2022,
      survey       = "acs5",
      output       = "wide",
      progress_bar = FALSE
    ) |> st_transform(4326) |> st_filter(bbox_sf)
    
    cat("Census: tracts in bbox:", nrow(dat), "\n")
    if (nrow(dat) == 0) return(NULL)
    
    # If a precise clip geometry is provided, filter tracts that intersect it
    if (!is.null(clip_geom)) {
      clip_geom <- tryCatch(
        st_transform(st_make_valid(clip_geom), 4326),
        error = function(e) NULL
      )
      if (!is.null(clip_geom)) {
        dat <- tryCatch(
          st_filter(dat, clip_geom),
          error = function(e) dat  # fall back to bbox if clip fails
        )
        cat("Census: tracts after clip:", nrow(dat), "\n")
        if (nrow(dat) == 0) return(NULL)
      }
    }
    
    # Compute one summary value per requested variable
    result <- list()
    for (k in variable_keys) {
      vs <- CENSUS_VARS[[k]]
      tryCatch({
        if (is.character(vs)) {
          col <- paste0(vs, "E")
          vals <- dat[[col]]
          result[[k]] <- median(vals[!is.na(vals) & vals > 0], na.rm = TRUE)
        } else {
          num_col   <- paste0(vs$num,   "E")
          denom_col <- paste0(vs$denom, "E")
          total_num   <- sum(dat[[num_col]],   na.rm = TRUE)
          total_denom <- sum(dat[[denom_col]], na.rm = TRUE)
          result[[k]] <- if (total_denom > 0) 100 * total_num / total_denom else NA_real_
        }
      }, error = function(e) { cat("Census var error [", k, "]:", e$message, "\n"); NULL })
    }
    result
  }, error = function(e) {
    cat("CENSUS FETCH ERROR:", e$message, "\n")
    warning(glue("Census summary fetch failed: {e$message}"))
    NULL
  })
}

# ── Helper: classify levee-protected vs levee-impacted areas ──────────────────
# levee_data is now the list returned by fetch_nld_levees():
#   $leveed_areas  = NLD polygons  → directly used as "protected"
#   $embankments + $floodwalls     → buffered to produce "impacted" zone
classify_levee_areas <- function(levee_data, buffer_m = 500) {
  # Protected: NLD Leveed Area polygons (direct, no buffering needed)
  protected <- levee_data$leveed_areas
  if (!is.null(protected) && nrow(protected) > 0) {
    protected <- protected |>
      st_make_valid() |>
      st_transform(4326)
  } else {
    protected <- NULL
  }
  
  # Impacted: buffer embankment + floodwall lines, subtract protected areas
  line_layers <- Filter(Negate(is.null), list(levee_data$embankments, levee_data$floodwalls))
  impacted <- NULL
  
  if (length(line_layers) > 0) {
    # Extract geometry only before combining — avoids column mismatch between layers
    lines_combined <- do.call(c, lapply(line_layers, function(l) {
      st_geometry(st_make_valid(st_transform(l, 5070)))
    }))
    buf <- st_union(st_buffer(lines_combined, buffer_m))
    
    # Subtract leveed areas from impact zone
    if (!is.null(protected) && nrow(protected) > 0) {
      prot_proj <- st_make_valid(st_transform(st_union(st_geometry(protected)), 5070))
      buf <- tryCatch(st_difference(buf, prot_proj), error = function(e) buf)
    }
    impacted <- st_transform(buf, 4326)
  }
  
  list(protected = protected, impacted = impacted)
}

# ── UI helpers ─────────────────────────────────────────────────────────────────
map_basemaps <- list(
  "CartoDB light" = providers$CartoDB.Positron,
  "CartoDB dark"  = providers$CartoDB.DarkMatter,
  "ESRI topo"     = providers$Esri.WorldTopoMap,
  "OpenStreetMap" = providers$OpenStreetMap
)

stat_card <- function(label, value, sublabel = NULL) {
  div(class = "stat-card",
      div(class = "stat-label", label),
      div(class = "stat-value",
          if (is.numeric(value)) formatC(value, format = "d", big.mark = ",") else as.character(value)
      ),
      if (!is.null(sublabel)) div(class = "stat-label", sublabel)
  )
}