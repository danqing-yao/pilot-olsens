-- =====================================================
-- raw_bite_bids_clean with deduplication
-- =====================================================
-- Deduplication logic:
--   For same inventoryId + value, keep only the first bid (earliest timestamp)
-- =====================================================

CREATE OR REPLACE TABLE `barnebys-skeleton.pilot_olsens.raw_bite_bids_clean`
CLUSTER BY inventoryId, auction_house_id
OPTIONS(
  description = "Cleaned Bite bids enriched with lot category and auction house info - deduplicated by inventoryId + value, keeping earliest timestamp"
)
AS

WITH bids_enriched AS (
  SELECT 
    b.programId,
    l.auction_house_id,
    ah.aucton_house_name,
    ah.is_skeleton_client,
    b.inventoryId,
    b.url,
    l.category_name,
    b.value,
    b.currency,
    b.source,
    b.sessionId,
    b.timestamp
  FROM `barnebys-skeleton.pilot_olsens.raw_bite_bids` b
  LEFT JOIN `barnebys-skeleton.pilot_olsens.raw_bbys_lots` l
    ON b.inventoryId = l.inventoryId
  LEFT JOIN `barnebys-skeleton.pilot_olsens.raw_auction_house` ah
    ON b.programId = ah.aucton_house_id
),

bids_ranked AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (
      PARTITION BY inventoryId, value
      ORDER BY timestamp ASC
    ) AS rn
  FROM bids_enriched
)

SELECT
  programId,
  auction_house_id,
  aucton_house_name,
  is_skeleton_client,
  inventoryId,
  url,
  category_name,
  value,
  currency,
  source,
  sessionId,
  timestamp
FROM bids_ranked
WHERE rn = 1;