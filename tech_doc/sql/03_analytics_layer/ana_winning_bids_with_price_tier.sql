-- =====================================================
-- Table 3: winning_bids_with_price_tier
-- Purpose: Winning bids only with price tier information
-- =====================================================

CREATE OR REPLACE TABLE `barnebys-skeleton.pilot_olsens.ana_winning_bids_with_price_tier`
CLUSTER BY price_tier, user_source_byfirstbid
OPTIONS(
  description = "Winning bids only with lot-level price tier information"
)
AS

SELECT 
  w.id AS inventoryId,
  w.WebUserid,
  w.user_source_byfirstbid,
  w.hammeredprice,
  w.enddate,
  w.month,
  w.category_name,
  w.sessionId,
  w.source,
  w.winning_sign,
  w.value,
  w.initialbidprice,
  -- Add price tier information
  t.price_tier,
  t.tier_order,
  t.tier_range,
  t.max_bid_price,
  t.p50_threshold,
  t.p80_threshold
FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning` w
LEFT JOIN `barnebys-skeleton.pilot_olsens.ana_lot_price_tiers` t
  ON CAST(w.id AS STRING) = t.inventoryId