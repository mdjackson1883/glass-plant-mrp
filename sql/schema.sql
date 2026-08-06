-- ============================================================
--  Bluegrass Glassworks — Plant Planning Database (DEMO)
-- ============================================================
--  A sanitized demonstration schema modeled on a real
--  production system built for a glass container plant.
--  All company names, item numbers, and quantities are
--  fictional / synthetically generated.
--
--  Target: SQLite 3 (also valid PostgreSQL with minor edits)
--  Author: Maria D. Jackson
-- ============================================================

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------
-- Reference: customers who buy finished glass containers
-- ------------------------------------------------------------
CREATE TABLE customers (
    customer_id   INTEGER PRIMARY KEY,
    customer_name TEXT NOT NULL UNIQUE,
    market        TEXT                          -- Spirits / Food / Beverage
);

-- ------------------------------------------------------------
-- Finished-good items (bottle specifications)
-- ------------------------------------------------------------
CREATE TABLE items (
    item_no      TEXT PRIMARY KEY,              -- plant mold number, e.g. 41207
    description  TEXT NOT NULL,
    customer_id  INTEGER REFERENCES customers(customer_id),
    capacity_ml  INTEGER,
    weight_oz    REAL,                          -- glass weight per bottle
    color        TEXT DEFAULT 'Flint'           -- Flint / Amber / Green
);

-- ------------------------------------------------------------
-- Load specifications: how a finished item is palletized.
-- One item can have multiple load specs (bulk vs carton,
-- customer-specific configurations).
-- ------------------------------------------------------------
CREATE TABLE load_specs (
    load_spec_no     TEXT PRIMARY KEY,          -- e.g. 210144
    item_no          TEXT NOT NULL REFERENCES items(item_no),
    pack_type        TEXT NOT NULL CHECK (pack_type IN ('Bulk','Carton')),
    pallet_footprint TEXT NOT NULL,             -- 40x48 / 44x56
    layers           INTEGER NOT NULL,
    glass_per_pallet INTEGER NOT NULL,          -- bottles per full pallet
    notes            TEXT
);

-- ------------------------------------------------------------
-- Dunnage components: the packaging materials consumed when
-- glass is palletized (pallets, tier sheets, top frames, ...)
-- ------------------------------------------------------------
CREATE TABLE dunnage_components (
    component_id TEXT PRIMARY KEY,              -- e.g. TIERSHEET_40x48
    description  TEXT NOT NULL,
    category     TEXT NOT NULL,                 -- pallet / tier_sheet / top_frame / hood
    item_number  TEXT                           -- purchasing item number
);

-- ------------------------------------------------------------
-- Dunnage bill of materials.
-- KEY DESIGN DECISION: the BOM grain is load_spec x component,
-- NOT item x component — because one item palletized two ways
-- consumes different dunnage.
-- ------------------------------------------------------------
CREATE TABLE dunnage_bom (
    load_spec_no   TEXT NOT NULL REFERENCES load_specs(load_spec_no),
    component_id   TEXT NOT NULL REFERENCES dunnage_components(component_id),
    qty_per_pallet REAL NOT NULL,
    PRIMARY KEY (load_spec_no, component_id)
);

-- ------------------------------------------------------------
-- Production lines (forming machines)
-- ------------------------------------------------------------
CREATE TABLE production_lines (
    line_no   INTEGER PRIMARY KEY,
    line_name TEXT NOT NULL
);

-- ------------------------------------------------------------
-- Production schedule: campaign runs per line.
-- speed_bpm = bottles per minute; efficiency = pack efficiency
-- (share of formed glass that survives to the pallet).
-- ------------------------------------------------------------
CREATE TABLE production_schedule (
    run_id       INTEGER PRIMARY KEY,
    line_no      INTEGER NOT NULL REFERENCES production_lines(line_no),
    item_no      TEXT NOT NULL REFERENCES items(item_no),
    load_spec_no TEXT NOT NULL REFERENCES load_specs(load_spec_no),
    start_date   TEXT NOT NULL,                 -- ISO yyyy-mm-dd
    end_date     TEXT NOT NULL,
    speed_bpm    REAL NOT NULL,
    efficiency   REAL NOT NULL DEFAULT 0.85
);

-- ------------------------------------------------------------
-- Current dunnage on-hand inventory (netting source)
-- ------------------------------------------------------------
CREATE TABLE dunnage_on_hand (
    component_id TEXT PRIMARY KEY REFERENCES dunnage_components(component_id),
    qty_on_hand  INTEGER NOT NULL DEFAULT 0
);

-- ------------------------------------------------------------
-- DERIVED: time-phased MRP output (rebuilt by Build-MRP.ps1)
-- ------------------------------------------------------------
CREATE TABLE mrp_daily (
    day          TEXT NOT NULL,
    component_id TEXT NOT NULL REFERENCES dunnage_components(component_id),
    gross_qty    INTEGER NOT NULL,
    net_qty      INTEGER NOT NULL,
    PRIMARY KEY (day, component_id)
);

-- Per-run contribution log powering dashboard drill-down
CREATE TABLE mrp_detail (
    day            TEXT NOT NULL,
    line_no        INTEGER NOT NULL,
    item_no        TEXT NOT NULL,
    load_spec_no   TEXT NOT NULL,
    component_id   TEXT NOT NULL,
    pallets        REAL NOT NULL,
    qty_per_pallet REAL NOT NULL,
    qty            INTEGER NOT NULL
);

-- ------------------------------------------------------------
-- Views
-- ------------------------------------------------------------

-- BOM with names attached, ready for explosion
CREATE VIEW v_dunnage_bom AS
SELECT b.load_spec_no,
       ls.item_no,
       ls.pack_type,
       ls.glass_per_pallet,
       b.component_id,
       dc.description AS component_desc,
       dc.category,
       b.qty_per_pallet
FROM dunnage_bom b
JOIN load_specs ls          ON ls.load_spec_no = b.load_spec_no
JOIN dunnage_components dc  ON dc.component_id = b.component_id;

-- MRP with component names + purchasing item numbers
CREATE VIEW v_mrp AS
SELECT m.day,
       m.component_id,
       dc.description AS component_desc,
       dc.item_number,
       m.gross_qty,
       m.net_qty
FROM mrp_daily m
JOIN dunnage_components dc ON dc.component_id = m.component_id;
