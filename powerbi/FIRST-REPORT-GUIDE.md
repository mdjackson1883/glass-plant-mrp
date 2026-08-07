# Your First Power BI Report — Step-by-Step

Goal: rebuild the dunnage MRP view as a Power BI report. When done, you'll have
a `.pbix` file for the portfolio repo AND "Power BI" earned honestly for your
resume skills list.

Total time: ~45-60 min the first time. Each numbered step is small — stop at
any ✅ CHECKPOINT and pick up later.

---

## Part 1 — Load the data (10 min)

1. Open **Power BI Desktop** (skip/close the sign-in popup — not required).
2. **Home ribbon → Get data → Text/CSV.**
3. Navigate to `Desktop\Portfolio\glass-plant-mrp\powerbi\data`, pick
   `mrp_daily.csv`, click **Load**.
4. Repeat Get data → Text/CSV for these five (skip the rest for now):
   - `dunnage_components.csv`
   - `dunnage_on_hand.csv`
   - `production_schedule.csv`
   - `items.csv`
   - `load_specs.csv`

✅ CHECKPOINT: the right-hand **Data** pane lists 6 tables.

## Part 2 — Relate the tables (5 min)

Power BI's version of SQL joins. It usually guesses right on its own.

5. Click the **Model view** icon (left edge, looks like three linked boxes).
6. Confirm (or drag-to-create) these lines between tables:
   - `mrp_daily.component_id` → `dunnage_components.component_id`
   - `dunnage_on_hand.component_id` → `dunnage_components.component_id`
   - `production_schedule.item_no` → `items.item_no`
   - `production_schedule.load_spec_no` → `load_specs.load_spec_no`
   - `load_specs.item_no` → `items.item_no`

✅ CHECKPOINT: every table connects to at least one other table.

## Part 3 — Three visuals (20 min)

Back to **Report view** (left edge, bar-chart icon).

**Visual 1 — KPI cards.**
7. Click the **Card** visual. Drag `mrp_daily → net_qty` into it. It shows the
   total net shortfall. Rename the title: "Net Shortfall (units)".
8. Add two more cards: `gross_qty` (Sum), and **Count** of
   `production_schedule → run_id` ("Scheduled Runs" — click the field's
   dropdown in the visual and pick *Count*).

**Visual 2 — shortfall over time.**
9. Click **Stacked column chart**. X-axis: `mrp_daily → day`.
   Y-axis: `net_qty`. Legend: `dunnage_components → description`.

**Visual 3 — the MRP matrix (your weekly pivot).**
10. Click **Matrix**. Rows: `dunnage_components → description`.
    Columns: `mrp_daily → day`. Values: `net_qty`.
11. Bonus polish: select the matrix → **Format** (paint roller) →
    Cell elements → turn on **Background color** conditional formatting on
    net_qty → white-to-red. Now shortfalls glow red like the HTML dashboard.

**Slicer (interactivity).**
12. Click **Slicer** visual, drag in `dunnage_components → category`.
    Click "pallet" and watch every visual filter itself. That's the demo moment.

✅ CHECKPOINT: page shows 3 cards, a column chart, a matrix, and a slicer.

## Part 4 — Save & ship (5 min)

13. **File → Save As** → `Desktop\Portfolio\glass-plant-mrp\powerbi\dunnage-mrp.pbix`
14. Tell Claude it's saved — we'll screenshot it, add it to the repo README,
    push it to GitHub, and add "Power BI" to the resume skills line.

---

### If something looks wrong
- Numbers way too big/small → the field is probably set to Count instead of
  Sum (or vice versa). Click the field's dropdown inside the visual.
- Chart ignores the slicer → the tables aren't related; recheck Part 2.
- Power BI feels slow → close Chrome tabs first; 6 GB RAM is tight but enough.
