-- =====================================================
-- proc_skeleton_auctions_with_enteredbids
-- =====================================================
-- Step 1: Match Bite records (url IS NOT NULL) with EnteredBid
--         - Strict match: inventoryId + amount + timestamp ≤1s
--         - Relaxed match: inventoryId + amount, closest timestamp
--         - Unmatched: enteredbidId, WebUserid, bidtype = NULL
-- Step 2: Fill winning records (url IS NULL) with bidid/winnerid/hammeredprice
-- Step 3: Infer source for remaining source IS NULL records based on WebUserid history
-- Step 4: Calculate user_source_byfirstbid per inventoryId + WebUserid
-- =====================================================

CREATE OR REPLACE TABLE `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_enteredbids`
CLUSTER BY id, auction_house_id
OPTIONS(
  description = "Skeleton auctions with Bite bids matched to EnteredBid, winning records filled, source inferred"
)
AS

WITH

-- =====================================================
-- Prepare base data: split Bite vs Winning records
-- =====================================================
bite_records AS (
  SELECT *
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_bite_bids`
  WHERE url IS NOT NULL
),

winning_records AS (
  SELECT *
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_bite_bids`
  WHERE url IS NULL
),

-- =====================================================
-- Prepare EnteredBid data
-- =====================================================
enteredbid_prepared AS (
  SELECT
    CAST(EnteredBidId AS STRING)  AS EnteredBidId,
    CAST(WebUserid AS STRING)     AS WebUserid,
    CAST(inventoryid AS STRING)   AS inventoryid,
    bid_amount,
    bidtime,
    bidtype,
    TIMESTAMP_TRUNC(bidtime, SECOND) AS bidtime_seconds
  FROM `barnebys-skeleton.pilot_olsens.raw_skeleton_enteredbids`
),

bite_prepared AS (
  SELECT
    *,
    CAST(id AS STRING)                        AS inventoryId_str,
    TIMESTAMP_TRUNC(timestamp, SECOND)        AS timestamp_seconds
  FROM bite_records
),

-- =====================================================
-- Step 1a: Strict match
-- =====================================================
strict_matched AS (
  SELECT * EXCEPT(match_rank)
  FROM (
    SELECT
      b.*,
      eb.EnteredBidId,
      eb.WebUserid,
      eb.bidtype,
      TRUE        AS has_enteredbid_match,
      'strict'    AS match_type,
      ROW_NUMBER() OVER (
        PARTITION BY b.inventoryId_str, b.value, b.timestamp
        ORDER BY eb.EnteredBidId ASC
      ) AS match_rank
    FROM bite_prepared b
    INNER JOIN enteredbid_prepared eb
      ON b.inventoryId_str = eb.inventoryid
      AND b.value = eb.bid_amount
      AND ABS(TIMESTAMP_DIFF(b.timestamp_seconds, eb.bidtime_seconds, SECOND)) <= 1
  )
  WHERE match_rank = 1
),

-- =====================================================
-- Step 1b: Relaxed match (only for unmatched by strict)
-- =====================================================
relaxed_matched_ranked AS (
  SELECT
    b.*,
    eb.EnteredBidId,
    eb.WebUserid,
    eb.bidtype,
    TRUE        AS has_enteredbid_match,
    'relaxed'   AS match_type,
    ROW_NUMBER() OVER (
      PARTITION BY b.inventoryId_str, b.value, b.timestamp
      ORDER BY ABS(TIMESTAMP_DIFF(b.timestamp_seconds, eb.bidtime_seconds, SECOND))
    ) AS match_rank
  FROM bite_prepared b
  INNER JOIN enteredbid_prepared eb
    ON b.inventoryId_str = eb.inventoryid
    AND b.value = eb.bid_amount
  WHERE NOT EXISTS (
    SELECT 1
    FROM strict_matched sm
    WHERE sm.inventoryId_str = b.inventoryId_str
      AND sm.value = b.value
      AND sm.timestamp = b.timestamp
  )
),

relaxed_matched AS (
  SELECT * EXCEPT(match_rank)
  FROM relaxed_matched_ranked
  WHERE match_rank = 1
),

-- =====================================================
-- Step 1c: Unmatched Bite records
-- =====================================================
unmatched AS (
  SELECT
    b.*,
    CAST(NULL AS STRING) AS EnteredBidId,
    CAST(NULL AS STRING) AS WebUserid,
    CAST(NULL AS STRING) AS bidtype,
    FALSE                AS has_enteredbid_match,
    'unmatched'          AS match_type
  FROM bite_prepared b
  WHERE NOT EXISTS (
    SELECT 1
    FROM enteredbid_prepared eb
    WHERE b.inventoryId_str = eb.inventoryid
      AND b.value = eb.bid_amount
  )
),

-- =====================================================
-- Step 1d: Combine all Bite records
-- =====================================================
all_bite_matched AS (
  SELECT * FROM strict_matched
  UNION ALL
  SELECT * FROM relaxed_matched
  UNION ALL
  SELECT * FROM unmatched
),

-- =====================================================
-- Step 2: Fill winning records (url IS NULL)
-- =====================================================
winning_filled AS (
  SELECT
    w.auctionid,
    w.startdate,
    w.enddate,
    w.month,
    w.id,
    w.skeletoncategory,
    w.bidid,
    w.winnerid,
    w.hammeredprice,
    w.initialbidprice,
    w.buyerspremium,
    w.currentcommission,
    3687                          AS auction_house_id,
    TRUE                          AS is_skeleton_client,
    w.url,                        -- NULL
    w.category_name,
    w.hammeredprice               AS value,
    'SEK'                         AS currency,
    w.source,                     -- NULL
    w.sessionId,                  -- NULL
    w.timestamp,                  -- NULL
    CAST(w.bidid AS STRING)       AS EnteredBidId,
    CAST(w.winnerid AS STRING)    AS WebUserid,
    CAST(NULL AS STRING)          AS bidtype,
    FALSE                         AS has_enteredbid_match,
    'winning'                     AS match_type
  FROM winning_records w
),

-- =====================================================
-- Step 3: Combine Bite + Winning, then infer source
-- =====================================================
combined AS (
  SELECT
    auctionid, startdate, enddate, month, id, skeletoncategory,
    bidid, winnerid, hammeredprice, initialbidprice, buyerspremium,
    currentcommission, auction_house_id, is_skeleton_client, url,
    category_name, value, currency, source, sessionId, timestamp,
    EnteredBidId, WebUserid, bidtype, has_enteredbid_match, match_type
  FROM all_bite_matched
  UNION ALL
  SELECT
    auctionid, startdate, enddate, month, id, skeletoncategory,
    bidid, winnerid, hammeredprice, initialbidprice, buyerspremium,
    currentcommission, auction_house_id, is_skeleton_client, url,
    category_name, value, currency, source, sessionId, timestamp,
    EnteredBidId, WebUserid, bidtype, has_enteredbid_match, match_type
  FROM winning_filled
),

-- Step 3a: Source statistics per WebUserid (based on all records)
user_source_stats AS (
  SELECT
    WebUserid,
    SUM(CASE WHEN source = 'barnebys' THEN 1 ELSE 0 END) AS barnebys_count,
    SUM(CASE WHEN source = 'other'    THEN 1 ELSE 0 END) AS other_count
  FROM combined
  WHERE WebUserid IS NOT NULL
    AND source IS NOT NULL
  GROUP BY WebUserid
),

-- Step 3b: First source by timestamp per WebUserid
user_first_source AS (
  SELECT WebUserid, source AS first_source_by_time
  FROM (
    SELECT
      WebUserid,
      source,
      ROW_NUMBER() OVER (PARTITION BY WebUserid ORDER BY timestamp ASC) AS rn
    FROM combined
    WHERE WebUserid IS NOT NULL
      AND source IS NOT NULL
  )
  WHERE rn = 1
),

-- Step 3c: Inferred source per WebUserid
user_inferred_source AS (
  SELECT
    s.WebUserid,
    CASE
      WHEN s.barnebys_count > s.other_count THEN 'barnebys'
      WHEN s.other_count > s.barnebys_count THEN 'other'
      ELSE COALESCE(f.first_source_by_time, 'other')
    END AS inferred_source
  FROM user_source_stats s
  LEFT JOIN user_first_source f ON s.WebUserid = f.WebUserid
),

-- Step 3d: Apply inferred source
combined_with_source AS (
  SELECT
    c.*,
    CASE
      WHEN c.source IS NULL THEN COALESCE(u.inferred_source, NULL)
      ELSE c.source
    END AS inferred_source_final
  FROM combined c
  LEFT JOIN user_inferred_source u ON c.WebUserid = u.WebUserid
),

-- =====================================================
-- Step 4: user_source_byfirstbid
-- =====================================================
first_source_per_user AS (
  SELECT DISTINCT
    id,
    WebUserid,
    FIRST_VALUE(inferred_source_final) OVER (
      PARTITION BY id, WebUserid
      ORDER BY timestamp ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_source
  FROM combined_with_source
  WHERE WebUserid IS NOT NULL
)

-- =====================================================
-- Final output
-- =====================================================
SELECT
  c.auctionid,
  c.startdate,
  c.enddate,
  c.month,
  c.id,
  c.skeletoncategory,
  c.bidid,
  c.winnerid,
  c.hammeredprice,
  c.initialbidprice,
  c.buyerspremium,
  c.currentcommission,
  c.auction_house_id,
  c.is_skeleton_client,
  c.url,
  c.category_name,
  c.value,
  c.currency,
  c.inferred_source_final  AS source,
  c.sessionId,
  c.timestamp,
  c.EnteredBidId,
  c.WebUserid,
  c.bidtype,
  c.has_enteredbid_match,
  c.match_type,
  CASE
    WHEN c.WebUserid IS NULL THEN c.inferred_source_final
    WHEN f.first_source = 'barnebys' THEN 'barnebys'
    ELSE c.inferred_source_final
  END AS user_source_byfirstbid
FROM combined_with_source c
LEFT JOIN first_source_per_user f
  ON c.id = f.id
  AND c.WebUserid = f.WebUserid


