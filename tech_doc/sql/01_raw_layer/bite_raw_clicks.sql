SELECT
  programid,
  url,
  clientip,
  dimension1,
  timestamp
FROM `barnebys-analytics.tracking.click`
WHERE
  timestamp >= "2025-01-01" AND timestamp < "2026-01-01"
  AND programid = '3687'