-- =====================================================
-- ana_bids_with_price_tier
-- Purpose: All bids with price tier information
-- Based on: proc_skeleton_auctions_with_enteredbids
--           ana_lot_price_tiers
-- =====================================================

CREATE OR REPLACE TABLE `barnebys-skeleton.pilot_olsens.ana_bids_with_price_tier`
CLUSTER BY price_tier, user_source_byfirstbid
OPTIONS(
  description = "All bids with lot-level price tier information"
)
AS

SELECT
  e.id                      AS inventoryId,
  e.WebUserid,
  e.user_source_byfirstbid,
  e.hammeredprice,
  e.enddate,
  e.month,
  e.category_name,
  e.sessionId,
  e.source,
  e.currency,
  t.price_tier,
  t.tier_order,
  t.tier_range,
  t.max_bid_price,
  t.p50_threshold,
  t.p80_threshold
FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_enteredbids` e
LEFT JOIN `barnebys-skeleton.pilot_olsens.ana_lot_price_tiers` t
  ON CAST(e.id AS STRING) = t.inventoryId
