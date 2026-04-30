# Flood Risk Explorer — R Shiny App

Interactive flood risk visualization, with toggleable HUC levels (2/4/8/12), NLCD land cover, National Levee
Database layers, Census demographics, and flood scenario overlays.

---
## How to use
### 1. Zoom to area of interest
### 2. Select HUC level of interest
### 3. Click "Load Layers of Current View" - Will load HUC boundaries within your zoomed in area. This may take a minute to load
### 4. Click on the specific HUC of interest. You may need to a wait for census data to load
This app is dynamically pulling from multiple online databases. It may take 30-60sec for each step to load

---
This app is an initial visualization tool for additional flood impact analysis due to undocumented levees. The full app will eventually include:
* Undocumented levee crests (lines) and footprints (polygons)
* Estimated protected and impacted (backwater) areas as a result of these structures
* Flood scenarios at 25-, 50-, 100-, and 500- year flood events along with levee structure failure thresholds and impacts

---

## Setup in consul

### 1. Install required packages

```r
install.packages(c(
  "shiny", "bslib", "leaflet", "leaflet.extras",
  "sf", "terra", "dplyr", "tidycensus", "tigris",
  "httr2", "jsonlite", "glue", "nhdplusTools"
))
```


### 2. Get a Census API key (free)

1. Request at <https://api.census.gov/data/key_signup.html>
2. Install it once in R:

```r
library(tidycensus)
census_api_key("YOUR_KEY_HERE", install = TRUE)
```


### 3. Run the app

```r
shiny::runApp
```

---

## App structure

```
flood_risk_app/
├── app.R          # Entry point
├── global.R       # Packages, constants, fetch helpers
├── ui.R           # bslib page layout + controls
├── server.R       # All reactive logic + map rendering
├── data/          # Local cache for downloaded data (future)
└── www/           # Static assets (CSS, JS overrides)
```

---

## Controls

| Control | Description |
|---------|-------------|
| **HUC level toggle** | Switches boundary display between HUC-2/4/8/12 from USGS NHD |
| **Flood scenario** | Filters FEMA zones: 25yr=X, 100yr=AE, 500yr=X500, failure=AE+A99 |
| **Levee-protected** | Shows FEMA Zone A99 polygons (levee-protected areas under NFIP) |
| **Levee-impacted** | Buffer zone around NLD levee centerlines (configurable 100–2000m) to represent "back flooding" areas |
| **NLCD layer** | MRLC WMS tile overlay (2021 land cover) |
| **Census Data Outputs** | ACS5 tract-level demographics (pop, income, race, housing) |
| **Custom extent** | Upload a .geojson or .gpkg to overlay your own flood scenario (will be added at a later point) |

---

## Data sources

| Layer | Source | Access method |
|-------|--------|---------------|
| NLCD 2021 | MRLC (USFS/USGS) | WMS tiles |
| National Levee Database | USACE | REST API |
| HUC boundaries | USGS NHD Plus | ArcGIS REST + GeoJSON |
| Census ACS5 | US Census Bureau | `tidycensus` package |

---

## Planned enhancements (roadmap)

- [ ] Local data caching (`data/` folder) to avoid re-fetching on every session
- [ ] Custom flood extent GeoTIFF ingest (raster scenario depth grids)
- [ ] Depth-damage curves for economic impact estimation
- [ ] Export: PNG map snapshot, CSV stats, GeoPackage of filtered layers
- [ ] Multi-HUC2 support / national view at HUC-2 level
- [ ] Streamflow gauge integration (USGS NWIS real-time)
- [ ] Levee condition ratings from NLD inspection records

---

## Notes on FEMA flood scenario mapping

This layers will be added at a later point to help the user analyze FEMA floodplains versus flood modeling outputs.
The app maps flood return periods to FEMA FIRM zone codes:

| Scenario | FIRM zones shown |
|----------|-----------------|
| 25-year  | Zone X (0.2% to 1% annual chance, outside 100yr) |
| 100-year | Zone A, AE, AH, AO, AR (1% annual chance) |
| 500-year | Zone X500, B (0.2% annual chance) |
| Levee failure | Zone AE + A99 (assumes protected area floods) |

These are regulatory zones — they represent the current mapped extents, not
dynamically modeled flood depths. For custom depth grids, use the file upload.

---
App development and code troubleshooting assisted by Claude.ai
