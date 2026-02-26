-- =====================================================
-- ana_funnel_olsens_excluded67
-- Summary Statistics by User Source (Long Format)
-- Based on: proc_skeleton_auctions_with_enteredbids
--           proc_skeleton_auctions_with_winning
--           ana_barnebys_increment
-- Time scope: 2025, excluding June & July
-- =====================================================

CREATE OR REPLACE TABLE `barnebys-skeleton.pilot_olsens.ana_funnel_olsens_exclued67`
AS

WITH

-- Total clicks from Bite
total_clicks AS (
  SELECT COUNT(*) AS clicks
  FROM `barnebys-skeleton.pilot_olsens.raw_bite_clicks`
  WHERE FORMAT_TIMESTAMP('%Y-%m', timestamp) BETWEEN '2025-01' AND '2025-12'
    AND FORMAT_TIMESTAMP('%Y-%m', timestamp) NOT IN ('2025-06', '2025-07')
),

-- Total unique inventory items with bids
total_items AS (
  SELECT COUNT(DISTINCT id) AS total_items_with_bids
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_enteredbids`
  WHERE month BETWEEN '2025-01' AND '2025-12'
    AND month NOT IN ('2025-06', '2025-07')
),

-- Registered users by source
registered_users AS (
  SELECT
    COALESCE(source, 'uncertain') AS source,
    COUNT(sessionId)              AS registered
  FROM `barnebys-skeleton.pilot_olsens.raw_bite_registrations`
  WHERE FORMAT_TIMESTAMP('%Y-%m', timestamp) BETWEEN '2025-01' AND '2025-12'
    AND FORMAT_TIMESTAMP('%Y-%m', timestamp) NOT IN ('2025-06', '2025-07')
  GROUP BY COALESCE(source, 'uncertain')
),

-- Bidding statistics by user source
stats_by_source_temp AS (
  SELECT
    COALESCE(user_source_byfirstbid, 'uncertain')              AS user_source_byfirstbid,
    COUNT(DISTINCT WebUserid)                                   AS bidders,
    COUNT(*)                                                    AS bid,
    COUNT(DISTINCT CASE
      WHEN WebUserid IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning` w
          WHERE w.WebUserid = t.WebUserid
            AND w.winning_sign = 'win'
            AND w.month BETWEEN '2025-01' AND '2025-12'
            AND w.month NOT IN ('2025-06', '2025-07')
        )
      THEN WebUserid
    END)                                                        AS unique_underbidders,
    COUNT(*) / NULLIF(COUNT(DISTINCT WebUserid), 0)             AS avg_bids_per_user
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_enteredbids` t
  WHERE month BETWEEN '2025-01' AND '2025-12'
    AND month NOT IN ('2025-06', '2025-07')
  GROUP BY COALESCE(user_source_byfirstbid, 'uncertain')
),

-- Winning statistics with commission fields
stats_by_source_winning AS (
  SELECT
    COALESCE(user_source_byfirstbid, 'uncertain')                              AS user_source_byfirstbid,
    COUNT(DISTINCT CASE WHEN winning_sign = 'win' THEN WebUserid END)          AS winners,
    COUNT(DISTINCT CASE WHEN winning_sign = 'win' THEN id END)                 AS total_winning_lots,
    SUM(CASE WHEN winning_sign = 'win' THEN hammeredprice ELSE 0 END)          AS total_winning_value,
    SUM(CASE WHEN winning_sign = 'win' THEN buyerspremium ELSE 0 END)          AS buyerspremium,
    SUM(CASE WHEN winning_sign = 'win' THEN currentcommission ELSE 0 END)      AS currentcommission,
    SUM(CASE WHEN winning_sign = 'win'
      THEN buyerspremium + currentcommission ELSE 0 END)                        AS total_commission
  FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_winning`
  WHERE month BETWEEN '2025-01' AND '2025-12'
    AND month NOT IN ('2025-06', '2025-07')
  GROUP BY COALESCE(user_source_byfirstbid, 'uncertain')
),

-- Users who bid on more than one lot
users_multiple_lots AS (
  SELECT
    user_source_byfirstbid,
    COUNT(DISTINCT WebUserid) AS users_bid_more_than_one_lot
  FROM (
    SELECT
      WebUserid,
      COALESCE(user_source_byfirstbid, 'uncertain') AS user_source_byfirstbid,
      COUNT(DISTINCT id)                            AS lot_count
    FROM `barnebys-skeleton.pilot_olsens.proc_skeleton_auctions_with_enteredbids`
    WHERE WebUserid IS NOT NULL
      AND month BETWEEN '2025-01' AND '2025-12'
      AND month NOT IN ('2025-06', '2025-07')
    GROUP BY WebUserid, COALESCE(user_source_byfirstbid, 'uncertain')
    HAVING COUNT(DISTINCT id) > 1
  )
  GROUP BY user_source_byfirstbid
),

-- Barnebys price increment by user source
barnebys_increment_stats AS (
  SELECT
    COALESCE(user_source_byfirstbid, 'uncertain') AS user_source_byfirstbid,
    SUM(barnebys_increment)                        AS barnebys_increment
  FROM `barnebys-skeleton.pilot_olsens.ana_barnebys_increment`
  WHERE month BETWEEN '2025-01' AND '2025-12'
    AND month NOT IN ('2025-06', '2025-07')
    AND barnebys_increment IS NOT NULL
  GROUP BY COALESCE(user_source_byfirstbid, 'uncertain')
),

-- Combine all statistics
stats_by_source AS (
  SELECT
    COALESCE(st.user_source_byfirstbid, sw.user_source_byfirstbid, ru.source) AS user_source,
    tc.clicks,
    ti.total_items_with_bids,
    COALESCE(ru.registered, 0)                    AS registered,
    COALESCE(st.bidders, 0)                        AS bidders,
    COALESCE(st.bid, 0)                            AS bid,
    COALESCE(st.unique_underbidders, 0)            AS unique_underbidders,
    ROUND(COALESCE(st.avg_bids_per_user, 0), 2)   AS avg_bids_per_user,
    COALESCE(um.users_bid_more_than_one_lot, 0)    AS users_bid_more_than_one_lot,
    COALESCE(sw.winners, 0)                        AS winners,
    COALESCE(sw.total_winning_lots, 0)             AS total_winning_lots,
    COALESCE(sw.total_winning_value, 0)            AS total_winning_value,
    ROUND(
      COALESCE(sw.total_winning_lots, 0) / NULLIF(COALESCE(sw.winners, 0), 0), 2
    )                                              AS avg_winning_lots_per_user,
    COALESCE(sw.buyerspremium, 0)                  AS buyerspremium,
    COALESCE(sw.currentcommission, 0)              AS currentcommission,
    COALESCE(sw.total_commission, 0)               AS total_commission,
    COALESCE(bi.barnebys_increment, 0)             AS barnebys_increment
  FROM stats_by_source_temp st
  FULL OUTER JOIN stats_by_source_winning sw
    ON st.user_source_byfirstbid = sw.user_source_byfirstbid
  FULL OUTER JOIN registered_users ru
    ON st.user_source_byfirstbid = ru.source
  LEFT JOIN users_multiple_lots um
    ON st.user_source_byfirstbid = um.user_source_byfirstbid
  LEFT JOIN barnebys_increment_stats bi
    ON st.user_source_byfirstbid = bi.user_source_byfirstbid
  CROSS JOIN total_clicks tc
  CROSS JOIN total_items ti
),

-- Add Total row
stats_with_total AS (
  SELECT * FROM stats_by_source

  UNION ALL

  SELECT
    'Total'                                                      AS user_source,
    MAX(clicks)                                                  AS clicks,
    MAX(total_items_with_bids)                                   AS total_items_with_bids,
    SUM(registered)                                              AS registered,
    SUM(bidders)                                                 AS bidders,
    SUM(bid)                                                     AS bid,
    SUM(unique_underbidders)                                     AS unique_underbidders,
    ROUND(SUM(bid) / NULLIF(SUM(bidders), 0), 2)                AS avg_bids_per_user,
    SUM(users_bid_more_than_one_lot)                             AS users_bid_more_than_one_lot,
    SUM(winners)                                                 AS winners,
    SUM(total_winning_lots)                                      AS total_winning_lots,
    SUM(total_winning_value)                                     AS total_winning_value,
    ROUND(SUM(total_winning_lots) / NULLIF(SUM(winners), 0), 2) AS avg_winning_lots_per_user,
    SUM(buyerspremium)                                           AS buyerspremium,
    SUM(currentcommission)                                       AS currentcommission,
    SUM(total_commission)                                        AS total_commission,
    SUM(barnebys_increment)                                      AS barnebys_increment
  FROM stats_by_source
),

-- Totals for percentage calculations
totals AS (
  SELECT
    MAX(clicks)                                                        AS total_clicks,
    MAX(CASE WHEN user_source = 'Total' THEN registered END)           AS total_registered,
    MAX(CASE WHEN user_source = 'Total' THEN bidders END)              AS total_bidders,
    MAX(CASE WHEN user_source = 'Total' THEN bid END)                  AS total_bid,
    MAX(CASE WHEN user_source = 'Total' THEN winners END)              AS total_winners,
    MAX(CASE WHEN user_source = 'Total' THEN total_winning_lots END)   AS total_winning_lots,
    MAX(CASE WHEN user_source = 'Total' THEN total_winning_value END)  AS total_winning_value
  FROM stats_with_total
),

-- Unpivot to long format
unpivoted AS (
  SELECT user_source, 'clicks'                      AS event_type, clicks                      AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'total_items_with_bids'       AS event_type, total_items_with_bids       AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'registered'                  AS event_type, registered                  AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'bidders'                     AS event_type, bidders                     AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'bid'                         AS event_type, bid                         AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'unique_underbidders'         AS event_type, unique_underbidders         AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'avg_bids_per_user'           AS event_type, avg_bids_per_user           AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'users_bid_more_than_one_lot' AS event_type, users_bid_more_than_one_lot AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'winners'                     AS event_type, winners                     AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'total_winning_lots'          AS event_type, total_winning_lots          AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'total_winning_value'         AS event_type, total_winning_value         AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'avg_winning_lots_per_user'   AS event_type, avg_winning_lots_per_user   AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'buyerspremium'               AS event_type, buyerspremium               AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'currentcommission'           AS event_type, currentcommission           AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'total_commission'            AS event_type, total_commission            AS value FROM stats_with_total
  UNION ALL
  SELECT user_source, 'barnebys_increment'          AS event_type, barnebys_increment          AS value FROM stats_with_total
)

-- Final output with percentages
SELECT
  u.event_type,
  u.user_source,
  CASE u.event_type
    WHEN 'clicks'                      THEN 1
    WHEN 'total_items_with_bids'       THEN 2
    WHEN 'registered'                  THEN 3
    WHEN 'bidders'                     THEN 4
    WHEN 'bid'                         THEN 5
    WHEN 'unique_underbidders'         THEN 6
    WHEN 'avg_bids_per_user'           THEN 7
    WHEN 'users_bid_more_than_one_lot' THEN 8
    WHEN 'winners'                     THEN 9
    WHEN 'total_winning_lots'          THEN 10
    WHEN 'total_winning_value'         THEN 11
    WHEN 'avg_winning_lots_per_user'   THEN 12
    WHEN 'buyerspremium'               THEN 13
    WHEN 'currentcommission'           THEN 14
    WHEN 'total_commission'            THEN 15
    WHEN 'barnebys_increment'          THEN 16
    ELSE 99
  END                                  AS event_order,
  u.value,
  tv.total_value,
  CASE
    WHEN u.user_source = 'barnebys' AND u.event_type = 'registered'
      THEN ROUND(u.value / NULLIF(t.total_registered, 0), 4)
    WHEN u.user_source = 'barnebys' AND u.event_type = 'bidders'
      THEN ROUND(u.value / NULLIF(t.total_bidders, 0), 4)
    WHEN u.user_source = 'barnebys' AND u.event_type = 'bid'
      THEN ROUND(u.value / NULLIF(t.total_bid, 0), 4)
    WHEN u.user_source = 'barnebys' AND u.event_type = 'winners'
      THEN ROUND(u.value / NULLIF(t.total_winners, 0), 4)
    WHEN u.user_source = 'barnebys' AND u.event_type = 'total_winning_lots'
      THEN ROUND(u.value / NULLIF(t.total_winning_lots, 0), 4)
    WHEN u.user_source = 'barnebys' AND u.event_type = 'total_winning_value'
      THEN ROUND(u.value / NULLIF(t.total_winning_value, 0), 4)
    ELSE NULL
  END                                  AS percentage_of_total,
  CASE
    WHEN u.user_source = 'barnebys' AND u.event_type = 'registered'
      THEN ROUND(u.value / NULLIF(t.total_clicks, 0), 4)
    WHEN u.user_source = 'barnebys' AND u.event_type = 'bidders'
      THEN ROUND(u.value / NULLIF(t.total_clicks, 0), 4)
    WHEN u.user_source = 'barnebys' AND u.event_type = 'winners'
      THEN ROUND(u.value / NULLIF(t.total_clicks, 0), 4)
    ELSE NULL
  END                                  AS percentage_of_clicks
FROM unpivoted u
CROSS JOIN totals t
LEFT JOIN (
  SELECT event_type, value AS total_value
  FROM unpivoted
  WHERE user_source = 'Total'
) tv ON u.event_type = tv.event_type
ORDER BY
  event_order,
  CASE
    WHEN user_source = 'barnebys'  THEN 1
    WHEN user_source = 'other'     THEN 2
    WHEN user_source = 'uncertain' THEN 3
    WHEN user_source = 'Total'     THEN 4
  END;