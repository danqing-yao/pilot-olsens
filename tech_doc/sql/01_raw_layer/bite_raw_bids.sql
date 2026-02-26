-- Query 3687 bids data from 202412-202512 - Filling empty inventoryId
WITH extracted_data AS (
  SELECT
    programId,
    url,
    category,
    action,
    label,
    value,
    currency,
    source,
    sessionId,
    timestamp,
    REGEXP_EXTRACT(
      REGEXP_EXTRACT(url, r'^[^?]+'), 
      r'(\d+)$'
    ) AS inventoryId_original
  FROM `barnebys-analytics.tracking.events`
  WHERE
    timestamp >= DATETIME("2024-12-01")
    AND timestamp < DATETIME("2026-01-01")
    AND programId = '3687'
    AND category = 'bid'
    AND action = 'placed'
    AND value IS NOT NULL
    AND TRIM(value) != ''
    AND LENGTH(value) > 0
),

-- Filling empty inventoryId
filled_inventoryId AS (
  SELECT
    programId,
    url,
    category,
    action,
    label,
    value,
    currency,
    source,
    sessionId,
    timestamp,
    inventoryId_original,
    -- Core logic: Populate with non-empty inventoryId entries sharing the same programId and label.
    COALESCE(
      inventoryId_original,
      FIRST_VALUE(inventoryId_original IGNORE NULLS) OVER (
        PARTITION BY programId, label
        ORDER BY CASE WHEN inventoryId_original IS NOT NULL THEN 0 ELSE 1 END
      )
    ) AS inventoryId
  FROM extracted_data
)

SELECT
  programId,
  inventoryId,
  url,
  category,
  action,
  label,
  value,
  currency,
  source,
  sessionId,
  timestamp
FROM filled_inventoryId
ORDER BY timestamp;