-- =====================================================
-- proc_skeleton_auctions_with_winning_sign
-- =====================================================
-- Step 1: Filter records with hammeredprice
-- Step 2: Mark winning_sign with 3 rules
--         - Rule 1: enteredbidId = bidid → win
--         - Rule 2: No bidid match → value >= hammeredprice → win
--         - Rule 3: No win at all → synthetic win
-- Step 3: Keep only smallest win per id + WebUserid
-- Step 4: Clean invalid records
-- Step 5: Replace win value with hammeredprice
-- Step 6: Add synthetic wins for id with no win
-- =====================================================

CREATE OR REPLACE TABLE `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning`
CLUSTER BY id, auction_house_id
OPTIONS(
  description = "Skeleton auctions with winning_sign, synthetic wins added for unmatched inventories"
)
AS

WITH

-- Step 1: Filter hammeredprice IS NOT NULL
bids_with_hammer AS (
  SELECT *
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_enteredbids`
  WHERE hammeredprice IS NOT NULL
),

-- Step 2a: Check if each id has enteredbidId = bidid match
inventory_has_winning_bidid AS (
  SELECT
    id,
    MAX(CASE
      WHEN enteredbidId = CAST(bidid AS STRING) THEN 1
      ELSE 0
    END) AS has_bidid_match
  FROM bids_with_hammer
  GROUP BY id
),

-- Step 2b: Mark winning_sign
bids_with_winning_sign AS (
  SELECT
    b.*,
    i.has_bidid_match,
    CASE
      -- Rule 1: Has bidid match
      WHEN i.has_bidid_match = 1 THEN
        CASE
          WHEN b.enteredbidId = CAST(b.bidid AS STRING) THEN 'win'
          ELSE 'not_win'
        END
      -- Rule 2: No bidid match, use value vs hammeredprice
      ELSE
        CASE
          WHEN b.value >= b.hammeredprice THEN 'win'
          ELSE 'not_win'
        END
    END AS winning_sign
  FROM bids_with_hammer b
  LEFT JOIN inventory_has_winning_bidid i ON b.id = i.id
),

-- Step 3: Keep only smallest win per id + WebUserid
bids_with_rank AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY id, WebUserid, winning_sign
      ORDER BY value ASC
    ) AS win_rank
  FROM bids_with_winning_sign
),

bids_filtered AS (
  SELECT * EXCEPT(win_rank, has_bidid_match)
  FROM bids_with_rank
  WHERE
    winning_sign = 'not_win'
    OR (winning_sign = 'win' AND win_rank = 1)
),

-- Step 4: Clean invalid records
-- Remove: WebUserid IS NULL + not_win + value > hammeredprice
bids_cleaned AS (
  SELECT *
  FROM bids_filtered
  WHERE NOT (
    WebUserid IS NULL
    AND winning_sign = 'not_win'
    AND value > hammeredprice
  )
),

-- Step 5: Replace win value with hammeredprice
bids_after_value_replacement AS (
  SELECT
    * EXCEPT(value),
    CASE
      WHEN winning_sign = 'win' THEN hammeredprice
      ELSE value
    END AS value
  FROM bids_cleaned
),

-- Step 6a: Identify id with no win at all
inventories_needing_synthetic_win AS (
  SELECT id
  FROM bids_after_value_replacement
  GROUP BY id
  HAVING
    SUM(CASE WHEN winning_sign = 'win' THEN 1 ELSE 0 END) = 0
    AND MAX(value) < MAX(hammeredprice)
),


-- Step 6b: Create synthetic win records
synthetic_wins AS (
  SELECT
    b.auctionid,
    b.startdate,
    b.enddate,
    b.month,
    b.id,
    b.skeletoncategory,
    b.bidid,
    b.winnerid,
    b.hammeredprice,
    b.initialbidprice,
    b.buyerspremium,
    b.currentcommission,
    b.auction_house_id,
    b.is_skeleton_client,
    CAST(NULL AS STRING)       AS url,
    b.category_name,
    b.currency,
    CAST(NULL AS STRING)       AS source,
    CAST(NULL AS INT64)        AS sessionId,
    CAST(NULL AS TIMESTAMP)    AS timestamp,
    b.bidid                    AS EnteredBidId,
    CAST(b.winnerid AS STRING) AS WebUserid,
    CAST(NULL AS STRING)       AS bidtype,
    FALSE                      AS has_enteredbid_match,
    'synthetic'                AS match_type,
    CAST(NULL AS STRING)       AS user_source_byfirstbid,
    'win'                      AS winning_sign,
    b.hammeredprice            AS value
  FROM (
    SELECT
      b.*,
      ROW_NUMBER() OVER (PARTITION BY b.id ORDER BY b.value DESC) AS rn
    FROM bids_after_value_replacement b
    INNER JOIN inventories_needing_synthetic_win i ON b.id = i.id
  ) b
  WHERE rn = 1
),

-- Step 6c: Combine
bids_final AS (
  SELECT * FROM bids_after_value_replacement
  UNION ALL
  SELECT * FROM synthetic_wins
)

-- Final output
SELECT
  auctionid,
  startdate,
  enddate,
  month,
  id,
  skeletoncategory,
  bidid,
  winnerid,
  hammeredprice,
  initialbidprice,
  buyerspremium,
  currentcommission,
  CASE WHEN winning_sign = 'win' 
    THEN buyerspremium + currentcommission 
    ELSE NULL 
  END AS total_commission,
  CASE WHEN winning_sign = 'win' 
    THEN ROUND(hammeredprice * 0.015, 2) 
    ELSE NULL 
  END AS ah_commission,
  auction_house_id,
  is_skeleton_client,
  url,
  category_name,
  value,
  currency,
  source,
  user_source_byfirstbid,
  sessionId,
  timestamp,
  enteredbidId,
  WebUserid,
  bidtype,
  has_enteredbid_match,
  match_type,
  winning_sign
FROM bids_final;