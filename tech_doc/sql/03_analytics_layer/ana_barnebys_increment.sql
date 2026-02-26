-- =====================================================
-- ana_barnebys_increment
-- Purpose: Calculate Barnebys price increment contribution
-- Based on: proc_skeleton_auctions_with_winning
--           ana_lot_price_tiers
-- =====================================================

CREATE OR REPLACE TABLE `barnebys-skeleton.pilot_olsens.ana_barnebys_increment`
CLUSTER BY id
OPTIONS(
  description = "Barnebys increment analysis with winner information (all inventories)"
)
AS

WITH

-- Step 1: Get all valid inventories
valid_inventories AS (
  SELECT
    id,
    MAX(hammeredprice)                                          AS hammeredprice,
    MAX(initialbidprice)                                        AS initialbidprice,
    MAX(enddate)                                                AS enddate,
    MAX(month)                                                  AS month
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning`
  GROUP BY id
),

-- Step 2: Find the first bid overall for each inventory
first_bid_overall AS (
  SELECT
    b.id,
    MIN(b.timestamp)                                            AS first_timestamp,
    ARRAY_AGG(b.user_source_byfirstbid ORDER BY b.timestamp LIMIT 1)[OFFSET(0)] AS first_bid_source
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning` b
  INNER JOIN valid_inventories v ON b.id = v.id
  GROUP BY b.id
),

-- Step 2.5: Check if inventory has ANY barnebys bids
has_barnebys_bid AS (
  SELECT
    id,
    MAX(CASE WHEN user_source_byfirstbid = 'barnebys' THEN 1 ELSE 0 END) AS has_barnebys
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning`
  GROUP BY id
),

-- Step 3: Find the first barnebys bid for each inventory
first_barnebys_bid AS (
  SELECT
    b.id,
    MIN(b.timestamp)                                            AS first_barnebys_timestamp,
    ARRAY_AGG(b.value ORDER BY b.timestamp LIMIT 1)[OFFSET(0)] AS first_barnebys_value
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning` b
  INNER JOIN valid_inventories v ON b.id = v.id
  WHERE b.user_source_byfirstbid = 'barnebys'
  GROUP BY b.id
),

-- Step 4: Get bids before first barnebys bid
bids_before_first_barnebys AS (
  SELECT
    b.id,
    b.value,
    fb.first_barnebys_value
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning` b
  INNER JOIN first_barnebys_bid fb ON b.id = fb.id
  WHERE b.timestamp < fb.first_barnebys_timestamp
),

-- Step 5: Find max value smaller than first barnebys value
max_value_before_barnebys AS (
  SELECT
    id,
    MAX(value) AS max_value_before
  FROM bids_before_first_barnebys
  WHERE value < first_barnebys_value
  GROUP BY id
),

-- Step 6: Calculate initial_price_before_first_barnebys_bid
initial_price_calc AS (
  SELECT
    v.id,
    v.initialbidprice,
    fo.first_bid_source,
    fb.first_barnebys_timestamp,
    mb.max_value_before,
    CASE
      WHEN fo.first_bid_source = 'barnebys' THEN v.initialbidprice
      ELSE COALESCE(mb.max_value_before, v.initialbidprice)
    END AS initial_price_before_first_barnebys_bid
  FROM valid_inventories v
  LEFT JOIN first_bid_overall fo       ON v.id = fo.id
  LEFT JOIN first_barnebys_bid fb      ON v.id = fb.id
  LEFT JOIN max_value_before_barnebys mb ON v.id = mb.id
),

-- Step 7: Calculate barnebys_final_bid
barnebys_final_bid_calc AS (
  SELECT
    b.id,
    MAX(b.value)     AS barnebys_final_bid,
    MAX(b.timestamp) AS barnebys_final_timestamp
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning` b
  INNER JOIN valid_inventories v ON b.id = v.id
  WHERE b.user_source_byfirstbid = 'barnebys'
    AND b.value <= v.hammeredprice
  GROUP BY b.id
),

-- Step 7.5: Get winner source
winner_info AS (
  SELECT
    id,
    ARRAY_AGG(user_source_byfirstbid ORDER BY timestamp DESC LIMIT 1)[OFFSET(0)] AS winner_source
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning`
  WHERE winning_sign = 'win'
  GROUP BY id
),

-- Step 8: Get price tier information
price_tier_info AS (
  SELECT DISTINCT
    inventoryId,
    price_tier,
    tier_order,
    tier_range
  FROM `barnebys-skeleton.pilot_olsens.ana_lot_price_tiers`
),

-- Step 9: Combine all calculations
-- Step 9: Combine all calculations
final_result AS (
  SELECT
    v.id,
    v.month,
    v.hammeredprice,
    v.initialbidprice,
    COALESCE(hb.has_barnebys, 0)                               AS has_barnebys,
    ip.initial_price_before_first_barnebys_bid,
    bf.barnebys_final_bid,
    CASE
      WHEN bf.barnebys_final_bid IS NOT NULL
        AND ip.initial_price_before_first_barnebys_bid IS NOT NULL
        THEN bf.barnebys_final_bid - ip.initial_price_before_first_barnebys_bid
      ELSE NULL
    END                                                        AS barnebys_increment,
    CASE
      WHEN wi.winner_source = 'barnebys' THEN 1
      ELSE 0
    END                                                        AS is_barnebys_win,
    wi.winner_source                                           AS user_source_byfirstbid, 
    pt.price_tier,
    pt.tier_order,
    pt.tier_range,
    ip.first_bid_source,
    CASE
      WHEN COALESCE(hb.has_barnebys, 0) = 0        THEN 'No Barnebys participation'
      WHEN bf.barnebys_final_bid IS NULL            THEN 'Has Barnebys bids but none valid'
      WHEN ip.first_bid_source = 'barnebys'         THEN 'Case 1: First bid is barnebys'
      WHEN ip.max_value_before IS NOT NULL          THEN 'Case 2: Found smaller previous bid'
      ELSE                                               'Case 2: No smaller previous bid, use initialbidprice'
    END                                                        AS calculation_method
  FROM valid_inventories v
  LEFT JOIN has_barnebys_bid hb        ON v.id = hb.id
  LEFT JOIN initial_price_calc ip      ON v.id = ip.id
  LEFT JOIN barnebys_final_bid_calc bf ON v.id = bf.id
  LEFT JOIN winner_info wi             ON v.id = wi.id
  LEFT JOIN price_tier_info pt         ON CAST(v.id AS STRING) = pt.inventoryId
)

SELECT
  id,
  month,
  hammeredprice,
  initialbidprice,
  has_barnebys,
  initial_price_before_first_barnebys_bid,
  barnebys_final_bid,
  barnebys_increment,
  is_barnebys_win,
  user_source_byfirstbid,
  price_tier,
  tier_order,
  tier_range,
  first_bid_source,
  calculation_method
FROM final_result
WHERE month IS NOT NULL;